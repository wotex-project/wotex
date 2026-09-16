defmodule Wotex.OPCUA.Open62541Test do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Error, Open62541}

  @options [
    executable: "/missing/native",
    executable_digest: String.duplicate("a", 64),
    guardian: "/missing/guardian",
    guardian_digest: String.duplicate("b", 64),
    endpoint: "opc.tcp://127.0.0.1:4840/fixture/",
    security_policy: :basic256sha256,
    security_mode: :sign_and_encrypt,
    client_uri: "urn:wotex:test:client",
    server_uri: "urn:wotex:test:server",
    certificate: "/missing/client.der",
    private_key: "/missing/client.key.der",
    server_certificate: "/missing/server.der",
    trust_certificate: "/missing/ca.der",
    crl: "/missing/clean.crl",
    authentication: %{type: :anonymous}
  ]

  setup_all do
    directory =
      Path.join(System.tmp_dir!(), "wotex-opcua-client-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    compiler = System.find_executable("cc") || flunk("native client tests require a C11 compiler")
    root = Path.expand("../../..", __DIR__)

    for {source, output} <- [
          {"priv/native/custody.c", "guardian"},
          {"test/native/host_probe.c", "probe"}
        ] do
      {diagnostic, status} =
        System.cmd(
          compiler,
          [
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            Path.join(root, source),
            "-o",
            Path.join(directory, output)
          ],
          stderr_to_stdout: true,
          env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
        )

      assert status == 0, diagnostic
    end

    %{directory: directory}
  end

  test "WOP-X01 one-shot connection validates configuration without reading files" do
    assert {:ok, handle} = Open62541.connect(Keyword.put(@options, :lifecycle, :oneshot))
    assert :ok = Open62541.disconnect(handle)
    assert :ok = Open62541.disconnect(handle)

    assert {:error, %Error{code: :invalid_native_configuration}} =
             Open62541.connect([{:security_mode, :none} | @options])

    assert {:error, %Error{code: :invalid_native_configuration}} = Open62541.connect(%{})
  end

  test "WOP-X01 invalid operations fail before one-shot file or process I/O" do
    assert {:ok, handle} = Open62541.connect(Keyword.put(@options, :lifecycle, :oneshot))

    for message <- [
          %{type: :read, node_id: "bad"},
          %{type: :read, node_id: "i=1", index_range: "1:2"},
          %{type: :write, node_id: "i=1", value: %{type: "Double", value: "not a number"}},
          %{type: :write, node_id: "i=1", value: %{type: "NodeId", value: "i=2"}},
          %{type: :write, node_id: "i=1", index_range: "1:2", value: %{type: "Double", value: 4.5}},
          %{type: :write, node_id: "i=1", value: 4.5},
          %{
            type: :write,
            node_id: "i=1",
            value: %{:type => "Double", "type" => "Double", :value => 4.5}
          },
          %{
            type: :call,
            node_id: "i=2",
            value: %{
              object_id: "i=85",
              arguments: List.duplicate(%{type: "Double", value: 1.0}, 65)
            }
          },
          %{type: :call, node_id: "i=2", value: %{object_id: "i=85", arguments: [], extra: true}}
        ] do
      assert {:error, %Error{}} = Open62541.request(handle, message, 100)
    end

    assert {:error, %Error{code: :unsupported_protocol}} =
             Open62541.request(handle, %{type: :browse, node_id: "i=85"}, 100)

    assert {:error, %Error{code: :invalid_native_handle}} =
             Open62541.request(handle, %{type: :read, node_id: "i=1"}, 0)

    assert {:error, %Error{code: :invalid_native_handle}} = Open62541.disconnect(%{})

    assert {:error, %Error{code: :invalid_native_handle}} =
             Open62541.request(%{handle | host: :forged}, %{type: :read, node_id: "i=1"}, 100)
  end

  test "WOP-X04 the facade retains no-effect for locally rejected native mutations" do
    assert {:ok, session} =
             Wotex.OPCUA.connect(
               @options
               |> Keyword.put(:lifecycle, :oneshot)
               |> Keyword.put(:client, Open62541)
             )

    assert {:error, %Error{code: :invalid_value, effect: :none}} =
             Wotex.OPCUA.send(session, %{
               type: :write,
               node_id: "ns=2;s=value",
               value: %{type: "Double", value: "bad"}
             })

    assert {:error, %Error{code: :invalid_value, effect: :none}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: "ns=2;s=method",
               value: %{object_id: "ns=0;i=85", arguments: [42]}
             })
  end

  test "WOP-X01 persistent connect rejects missing credential files before process startup" do
    assert {:error, %Error{code: :invalid_native_configuration}} =
             Open62541.connect(@options)
  end

  test "WOP-X01 persistent native client owns open, services and close", context do
    options = fixture(context, "persistent")
    assert {:ok, handle} = Open62541.connect(options)

    assert {:ok, %{"value" => %{"value" => 21.5}}} =
             Open62541.request(handle, %{type: :read, node_id: "ns=2;s=value"}, 1000)

    assert {:ok, %{"status" => 0}} =
             Open62541.request(
               handle,
               %{type: :write, node_id: "ns=2;s=value", value: %{type: "Double", value: 4.5}},
               1000
             )

    assert {:ok, %{"status" => 0}} =
             Open62541.request(
               handle,
               %{
                 type: :write,
                 node_id: "ns=2;s=value",
                 value: %{type: "ByteString", value: <<0, 255>>}
               },
               1000
             )

    assert {:ok, %{"status" => 0}} =
             Open62541.request(
               handle,
               %{
                 type: :write,
                 node_id: "ns=2;s=value",
                 value: %{"type" => "ByteString", "array" => true, "value" => [<<0, 255>>, nil]}
               },
               1000
             )

    assert {:ok, %{"status" => 0}} =
             Open62541.request(
               handle,
               %{
                 type: :write,
                 node_id: "ns=2;s=value",
                 value: %{"type" => "Double", "value" => 4.5}
               },
               1000
             )

    assert {:ok, %{"outputs" => [%{"value" => 4.5}]}} =
             Open62541.request(
               handle,
               %{
                 type: :call,
                 node_id: "ns=2;s=method",
                 value: %{
                   object_id: "ns=0;i=85",
                   arguments: [%{type: "Double", value: 1.25}, %{type: "Double", value: 3.25}]
                 }
               },
               1000
             )

    assert :ok = Open62541.disconnect(handle)
    assert :ok = Open62541.disconnect(handle)
  end

  test "WOP-X01 one-shot native client opens and closes within each read", context do
    options = fixture(context, "oneshot")
    assert {:ok, handle} = Open62541.connect(Keyword.put(options, :lifecycle, :oneshot))

    assert {:ok, %{"value" => %{"value" => 21.5}}} =
             Open62541.request(handle, %{type: :read, node_id: "ns=2;s=value"}, 2000)

    assert :ok = Open62541.disconnect(handle)
  end

  test "WOP-X01 failed secure activation closes the native owner", context do
    options = fixture(context, "badopen", "session_reply")
    options = Keyword.put(options, :session_timeout_ms, 61_000)

    assert {:error, %Error{}} = Open62541.connect(options)

    oneshot_options =
      context
      |> fixture("badopen-oneshot", "session_reply")
      |> Keyword.merge(lifecycle: :oneshot, session_timeout_ms: 61_000)

    assert {:ok, oneshot} = Open62541.connect(oneshot_options)

    assert {:error, %Error{}} =
             Open62541.request(oneshot, %{type: :read, node_id: "ns=2;s=value"}, 2000)
  end

  defp fixture(context, name, mode \\ "session_services") do
    directory = Path.join(context.directory, name)
    File.mkdir!(directory)
    executable = Path.join(directory, mode)
    File.cp!(Path.join(context.directory, "probe"), executable)
    File.chmod!(executable, 0o700)

    files =
      for field <- [:certificate, :private_key, :server_certificate, :trust_certificate, :crl] do
        path = Path.join(directory, Atom.to_string(field) <> ".der")
        File.write!(path, Atom.to_string(field))
        {field, path}
      end

    @options
    |> Keyword.merge(files)
    |> Keyword.merge(
      executable: executable,
      executable_digest: digest(executable),
      guardian: Path.join(context.directory, "guardian"),
      guardian_digest: digest(Path.join(context.directory, "guardian")),
      timeout: 2000
    )
  end

  defp digest(path),
    do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
