defmodule Wotex.OPCUA.Native.ConfigTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.Config

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-opcua-config-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    fields = [:certificate, :private_key, :server_certificate, :trust_certificate, :crl]

    files =
      Map.new(fields, fn field ->
        path = Path.join(directory, Atom.to_string(field) <> ".der")
        File.write!(path, Atom.to_string(field))
        {field, path}
      end)

    options =
      [
        executable: Path.join(directory, "native"),
        executable_digest: String.duplicate("a", 64),
        guardian: Path.join(directory, "guardian"),
        guardian_digest: String.duplicate("b", 64),
        endpoint: "opc.tcp://127.0.0.1:4840/fixture/",
        security_policy: :basic256sha256,
        security_mode: :sign_and_encrypt,
        client_uri: "urn:wotex:test:client",
        server_uri: "urn:wotex:test:server",
        authentication: %{type: :anonymous}
      ] ++ Map.to_list(files)

    %{options: options, files: files}
  end

  test "WOP-X01 validates and snapshots the exact Python-free native open shape", context do
    assert {:ok, config} = Config.new(context.options)

    assert {:ok, parameters} =
             Config.open_parameters(config, System.monotonic_time(:millisecond) + 1000)

    assert Map.keys(parameters) |> length() == 12
    assert parameters["security_mode"] == "SignAndEncrypt"
    assert parameters["authentication"] == %{"type" => "anonymous"}
    assert parameters["session_timeout_ms"] == 60_000

    assert parameters["certificate"] ==
             %{"type" => "bytes", "base64" => Base.encode64("certificate")}

    refute inspect(config) =~ context.files.private_key
  end

  test "WOP-X01 rejects duplicate, unknown, insecure and malformed credential options before I/O",
       context do
    invalid = [
      [{:timeout, 1000} | [{:timeout, 2000} | context.options]],
      [{:unreviewed, true} | context.options],
      Keyword.put(context.options, :security_mode, :none),
      Keyword.put(context.options, :security_policy, :unknown),
      Keyword.put(context.options, :authentication, %{type: :unsupported}),
      Keyword.put(context.options, :authentication, %{
        type: :username,
        username: "a",
        password: <<0>>,
        extra: true
      }),
      Keyword.put(context.options, :authentication, %{
        type: :certificate,
        certificate: "relative",
        private_key: "/tmp/key"
      })
    ]

    for options <- invalid do
      assert {:error, %Error{code: :invalid_native_configuration}} = Config.new(options)
    end
  end

  test "WOP-X01 bounds each credential file and the original deadline", context do
    assert {:ok, config} = Config.new(context.options)

    assert {:error, %Error{code: :deadline_exceeded}} =
             Config.open_parameters(config, System.monotonic_time(:millisecond) - 1)

    File.write!(context.files.certificate, :binary.copy("x", 65_537))

    assert {:error, %Error{code: :invalid_native_configuration}} =
             Config.open_parameters(config, System.monotonic_time(:millisecond) + 1000)

    assert {:error, %Error{code: :invalid_native_configuration}} =
             Config.open_parameters(
               %{config | security_policy: :unknown},
               System.monotonic_time(:millisecond) + 1000
             )
  end

  test "WOP-X01 projects binary username and certificate token forms without secret inspection",
       context do
    username = %{type: :username, username: "operator", password: <<0, 255>>}

    assert {:ok, config} =
             context.options
             |> Keyword.put(:authentication, username)
             |> Config.new()

    assert {:ok, %{"authentication" => token}} =
             Config.open_parameters(config, System.monotonic_time(:millisecond) + 1000)

    assert token == %{
             "type" => "username",
             "username" => "operator",
             "password" => %{"type" => "bytes", "base64" => "AP8="}
           }

    refute inspect(config) =~ "operator"

    certificate = %{
      type: :certificate,
      certificate: context.files.certificate,
      private_key: context.files.private_key
    }

    assert {:ok, certificate_config} =
             context.options
             |> Keyword.put(:authentication, certificate)
             |> Config.new()

    assert {:ok, %{"authentication" => certificate_token}} =
             Config.open_parameters(certificate_config, System.monotonic_time(:millisecond) + 1000)

    assert certificate_token["certificate"] ==
             %{"type" => "bytes", "base64" => Base.encode64("certificate")}
  end

  test "WOP-X01 rejects an aggregate credential frame over the IPC limit", context do
    assert {:ok, config} = Config.new(context.options)

    for path <- Map.values(context.files) do
      File.write!(path, :binary.copy("x", 30_000))
    end

    assert {:error, %Error{code: :request_too_large}} =
             Config.open_parameters(config, System.monotonic_time(:millisecond) + 1000)

    assert {:error, %Error{code: :invalid_native_configuration}} = Config.new(%{})

    assert {:error, %Error{code: :invalid_native_configuration}} =
             Config.open_parameters(%{}, System.monotonic_time(:millisecond) + 1000)
  end
end
