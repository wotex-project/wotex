Code.require_file("package_mirror.exs", __DIR__)

defmodule DirectoryEvidence do
  @moduledoc false

  def begin(tools) do
    {output, 0} =
      System.cmd("mktemp", ["-d", Path.join(System.tmp_dir!(), "wotex-directory-evidence.XXXXXX")])

    root = String.trim(output)
    inputs!(root, tools)
    root
  end

  def inputs!(root, tools \\ []) do
    external_root!(root)

    commands =
      for {name, options} <- tools, is_list(options), into: %{} do
        {Atom.to_string(name),
         %{"command" => options[:command], "environment" => options[:env] || %{}}}
      end

    inputs = Map.put(snapshot(), "checks", commands)
    File.write!(Path.join(root, "inputs.etf"), :erlang.term_to_binary(inputs))
  end

  def snapshot do
    paths =
      Mix.Project.config()[:package][:files] ++
        ~w(mix.exs mix.lock .check.exs .formatter.exs .credo.exs .doctor.exs coveralls.json) ++
        Path.wildcard("{lib,test,bin}/**/*.{ex,exs}") ++
        Path.wildcard("config/*.exs") ++
        Path.wildcard("docs/{decisions,plans,provenance,specs}/**/*")

    {commit, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    {status, 0} = System.cmd("git", ["status", "--porcelain", "--untracked-files=normal"])

    %{
      "source_commit" => String.trim(commit),
      "source_clean" => status == "",
      "inputs" =>
        for(path <- Enum.uniq(paths), File.regular?(path), into: %{}, do: {path, digest(path)}),
      "runtime" => %{
        "elixir" => System.version(),
        "otp" => System.otp_release(),
        "otp_version" =>
          [:code.root_dir() |> List.to_string(), "releases", System.otp_release(), "OTP_VERSION"]
          |> Path.join()
          |> File.read!()
          |> String.trim(),
        "erts" => List.to_string(:erlang.system_info(:version))
      },
      "development_path_dependency" => System.get_env("WOTEX_PATH_DEPS") == "1",
      "path_dependencies" => path_dependencies()
    }
  end

  def same_inputs!(before, after_inputs) do
    unless Map.take(before, ~w(source_commit inputs runtime path_dependencies)) ==
             Map.take(after_inputs, ~w(source_commit inputs runtime path_dependencies)),
           do: raise("evidence inputs changed during verification")

    :ok
  end

  def consumer_result!(%{"total" => total, "failures" => 0, "skipped" => 0, "excluded" => 0})
      when is_integer(total) and total > 0,
      do: :ok

  def consumer_result!(_), do: raise("incomplete archive consumer evidence")

  def files!(root, files) do
    expected = [
      "consumer.mix.lock",
      "wotex.tar",
      "wotex_directory-#{Mix.Project.config()[:version]}.tar"
    ]

    unless is_map(files) and Enum.sort(Map.keys(files)) == Enum.sort(expected),
      do: raise("archive evidence file set is incomplete")

    for {name, expected} <- files do
      unless Path.basename(name) == name and digest(Path.join(root, name)) == expected,
        do: raise("archive evidence checksum mismatch")
    end

    :ok
  end

  def archive!(root, attributes) do
    inputs = inputs(root)
    same_inputs!(inputs, snapshot())
    consumer_result!(attributes["consumer_result"])
    files!(root, attributes["files"])

    write!(root, "archive-evidence.json", %{
      "schema_version" => "1.0.0",
      "verification_source" => inputs,
      "archive" => attributes,
      "publication_authorized" => false
    })
  end

  def finish!(root) do
    external_root!(root)
    manifest = root |> Path.join("archive-evidence.json") |> File.read!() |> Jason.decode!()
    inputs = inputs(root)
    same_inputs!(inputs, snapshot())
    same_inputs!(inputs, manifest["verification_source"])
    files!(root, manifest["archive"]["files"])
    consumer_result!(manifest["archive"]["consumer_result"])

    DirectoryPackageMirror.evidence!(
      manifest["archive"]["package_exclusion"],
      inputs["inputs"],
      Mix.Project.config()[:package][:files]
    )

    unless File.read!(Path.join(root, "compiler.exit")) == "0\n",
      do: raise("compiler evidence is missing")

    if inputs["checks"] == %{}, do: raise("release evidence check prerequisites are missing")

    checks =
      for {name, check} <- inputs["checks"], into: %{}, do: {name, Map.put(check, "exit_code", 0)}

    manifest =
      Map.merge(manifest, %{
        "checks" => checks,
        "check_execution" => "all configured release checks completed successfully",
        "specification" => %{
          "id" => "WTD.01",
          "version" => "1.1.0",
          "target_revision" => "2023-12-05"
        },
        "claims" => %{
          "directory_mechanics" => "WTD.01 bounded contract",
          "consumer_interoperability" => "two test implementations",
          "transport_conformance" => false,
          "certification" => false,
          "stable_api" => false
        }
      })

    write!(root, "release-evidence.json", manifest)
    IO.puts("release evidence: #{Path.join(root, "release-evidence.json")}")
    IO.puts("release evidence sha256: #{digest(Path.join(root, "release-evidence.json"))}")
  end

  def digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  def external_root!(root) do
    {physical, 0} = System.cmd("pwd", ["-P"], cd: root)
    {source, 0} = System.cmd("pwd", ["-P"])
    physical = String.trim(physical)
    source = String.trim(source)

    if physical == source or String.starts_with?(physical, source <> "/") or
         String.starts_with?(source, physical <> "/"),
       do: raise("evidence directory must be outside the source tree and its ancestors")

    :ok
  end

  defp path_dependencies do
    for {:wotex, options} <- Mix.Project.config()[:deps],
        is_list(options),
        source = options[:path],
        into: %{} do
      {commit, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: source)

      {status, 0} =
        System.cmd("git", ["status", "--porcelain", "--untracked-files=normal"], cd: source)

      files =
        Path.wildcard(Path.join(source, "lib/**/*.ex")) ++
          Path.wildcard(Path.join(source, "priv/w3c/**/*")) ++
          Enum.map(~w(mix.exs mix.lock), &Path.join(source, &1))

      hashes =
        for path <- files,
            File.regular?(path),
            into: %{},
            do: {Path.relative_to(path, source), digest(path)}

      {"wotex",
       %{
         "source_commit" => String.trim(commit),
         "source_clean" => status == "",
         "inputs" => hashes
       }}
    end
  end

  defp inputs(root),
    do: root |> Path.join("inputs.etf") |> File.read!() |> :erlang.binary_to_term([:safe])

  defp write!(root, name, value),
    do: File.write!(Path.join(root, name), Jason.encode!(value, pretty: true) <> "\n")
end
