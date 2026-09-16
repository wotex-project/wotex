defmodule Wotex.CoAP.PKIFixtureGenerator do
  @moduledoc false

  @profiles [
    {"client", "DNS:client.fixture.test", "digitalSignature", "clientAuth", ""},
    {"server", "DNS:fixture.test,IP:127.0.0.1", "digitalSignature", "serverAuth", ""},
    {"wrong-san", "DNS:wrong.test", "digitalSignature", "serverAuth", ""},
    {"expired", "DNS:fixture.test", "digitalSignature", "serverAuth", ""},
    {"revoked", "DNS:fixture.test", "digitalSignature", "serverAuth", ""},
    {"wrong-ku", "DNS:fixture.test", "keyEncipherment", "serverAuth", ""},
    {"wrong-eku", "DNS:fixture.test", "digitalSignature", "clientAuth", ""},
    {"critical", "DNS:fixture.test", "digitalSignature", "serverAuth",
     "1.2.3.4=critical,DER:01:01:FF\n"},
    {"cn-only", nil, "digitalSignature", "serverAuth", ""},
    {"wildcard", "DNS:*.fixture.test", "digitalSignature", "serverAuth", ""},
    {"weak", "DNS:fixture.test", "digitalSignature", "serverAuth", ""}
  ]

  @base """
  [ca]
  default_ca=authority
  [authority]
  database=index
  new_certs_dir=newcerts
  certificate=root.pem
  private_key=root.key
  serial=serial
  crlnumber=crlnumber
  default_md=sha256
  default_crl_days=36500
  policy=names
  unique_subject=no
  [names]
  commonName=supplied
  [extensions]
  basicConstraints=critical,CA:FALSE
  """

  @spec main([String.t()]) :: :ok
  def main(arguments) do
    {options, positional, invalid} =
      OptionParser.parse(arguments, strict: [openssl: :string, output: :string])

    with [] <- positional,
         [] <- invalid,
         output when is_binary(output) <- options[:output],
         {:ok, openssl} <- executable(options[:openssl] || "openssl") do
      generate(openssl, Path.expand(output))
    else
      _ ->
        raise "usage: mix run bin/generate_dtls_pki.exs --output PATH [--openssl PATH]"
    end
  end

  @spec generate(String.t(), String.t()) :: :ok
  def generate(openssl, output) do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-pki-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(output)
    File.mkdir!(workspace)
    File.chmod!(workspace, 0o700)

    try do
      generate_authorities(openssl, workspace, output)
      initialize_authority(workspace)
      Enum.each(@profiles, &generate_profile(openssl, workspace, output, &1))
      generate_formats(openssl, workspace, output)
      generate_crls(openssl, workspace, output)
      write_manifest(openssl, output)
    after
      File.rm_rf!(workspace)
    end
  end

  defp generate_authorities(openssl, workspace, output) do
    for {name, common_name} <- [
          {"root", "Wotex Public Test Root"},
          {"untrusted-root", "Wotex Public Other Test Root"}
        ] do
      key(openssl, workspace, name, 2048)

      run(openssl, workspace, [
        "req",
        "-new",
        "-x509",
        "-key",
        "#{name}.key",
        "-out",
        "#{name}.pem",
        "-days",
        "36500",
        "-subj",
        "/CN=#{common_name}",
        "-addext",
        "basicConstraints=critical,CA:TRUE",
        "-addext",
        "keyUsage=critical,keyCertSign,cRLSign"
      ])
    end

    run(openssl, workspace, [
      "x509",
      "-in",
      "untrusted-root.pem",
      "-outform",
      "DER",
      "-out",
      Path.join(output, "untrusted-root.der")
    ])
  end

  defp initialize_authority(workspace) do
    File.write!(Path.join(workspace, "index"), "")
    File.write!(Path.join(workspace, "serial"), "1000\n")
    File.write!(Path.join(workspace, "crlnumber"), "1000\n")
    File.mkdir!(Path.join(workspace, "newcerts"))
  end

  defp generate_profile(openssl, workspace, output, {name, san, usage, extended, extra}) do
    key(openssl, workspace, name, if(name == "weak", do: 1024, else: 2048))

    configuration =
      @base <>
        "keyUsage=critical,#{usage}\nextendedKeyUsage=#{extended}\n" <>
        extra <>
        if(san, do: "subjectAltName=#{san}\n", else: "")

    File.write!(Path.join(workspace, "ca.cnf"), configuration)

    run(openssl, workspace, [
      "req",
      "-new",
      "-key",
      "#{name}.key",
      "-out",
      "#{name}.csr",
      "-subj",
      "/CN=fixture.test"
    ])

    {start_date, end_date} =
      if name == "expired",
        do: {"20000101000000Z", "20010101000000Z"},
        else: {"20200101000000Z", "20991231235959Z"}

    run(openssl, workspace, [
      "ca",
      "-batch",
      "-config",
      "ca.cnf",
      "-extensions",
      "extensions",
      "-notext",
      "-in",
      "#{name}.csr",
      "-out",
      "#{name}.pem",
      "-startdate",
      start_date,
      "-enddate",
      end_date
    ])

    convert(openssl, workspace, "x509", "#{name}.pem", Path.join(output, "#{name}.der"))

    run(openssl, workspace, [
      "rsa",
      "-in",
      "#{name}.key",
      "-traditional",
      "-outform",
      "DER",
      "-out",
      Path.join(output, "#{name}-key.der")
    ])
  end

  defp generate_formats(openssl, workspace, output) do
    run(openssl, workspace, [
      "pkcs8",
      "-topk8",
      "-nocrypt",
      "-in",
      "client.key",
      "-outform",
      "DER",
      "-out",
      Path.join(output, "client-pkcs8.der")
    ])

    convert(openssl, workspace, "x509", "root.pem", Path.join(output, "root.der"))
  end

  defp generate_crls(openssl, workspace, output) do
    crl(openssl, workspace, output, "valid", "20200101000000Z", "20991231235959Z")
    crl(openssl, workspace, output, "expired", "20000101000000Z", "20010101000000Z")
    run(openssl, workspace, ["ca", "-revoke", "revoked.pem", "-config", "ca.cnf"])
    crl(openssl, workspace, output, "revoked", "20200101000000Z", "20991231235959Z")
  end

  defp crl(openssl, workspace, output, name, last_update, next_update) do
    run(openssl, workspace, [
      "ca",
      "-gencrl",
      "-config",
      "ca.cnf",
      "-out",
      "#{name}.crl",
      "-crl_lastupdate",
      last_update,
      "-crl_nextupdate",
      next_update
    ])

    convert(openssl, workspace, "crl", "#{name}.crl", Path.join(output, "#{name}-crl.der"))
  end

  defp convert(openssl, workspace, command, input, output) do
    run(openssl, workspace, [command, "-in", input, "-outform", "DER", "-out", output])
  end

  defp key(openssl, workspace, name, bits) do
    run(openssl, workspace, ["genrsa", "-out", "#{name}.key", Integer.to_string(bits)])
  end

  defp write_manifest(openssl, output) do
    files =
      output
      |> Path.join("*.der")
      |> Path.wildcard()
      |> Enum.sort()
      |> Map.new(fn path -> {Path.basename(path), digest(path)} end)

    {version, 0} =
      System.cmd(openssl, ["version", "-a"],
        stderr_to_stdout: true,
        env: clean_environment()
      )

    manifest = %{
      "schema" => "wotex-coap-public-pki-fixtures-v1",
      "purpose" => "public test-only credentials",
      "openssl" => version,
      "files" => files
    }

    File.write!(Path.join(output, "manifest.json"), Jason.encode!(manifest, pretty: true) <> "\n")
    :ok
  end

  defp digest(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp executable(path) do
    case System.find_executable(path) do
      nil -> {:error, :openssl_not_found}
      executable -> {:ok, executable}
    end
  end

  defp run(openssl, workspace, arguments) do
    case System.cmd(openssl, arguments,
           cd: workspace,
           stderr_to_stdout: true,
           env: clean_environment()
         ) do
      {_, 0} -> :ok
      {output, status} -> raise "OpenSSL fixture command failed (#{status}): #{output}"
    end
  end

  defp clean_environment do
    Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)
  end
end

Wotex.CoAP.PKIFixtureGenerator.main(System.argv())
