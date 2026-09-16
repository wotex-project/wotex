defmodule Wotex.OPCUA.NativeSecureInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias Wotex.OPCUA.Native.{Config, Frame, Host, Ready}
  @moduletag :interop

  test "a pinned native SDK channel activates and reads the server NamespaceArray" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    probe = System.fetch_env!("WOTEX_OPCUA_NATIVE_PROBE")
    parameters = Path.join(Path.dirname(config), "native-open.json")

    assert File.regular?(probe)
    assert File.regular?(parameters)

    {output, 0} =
      System.cmd(probe, [parameters],
        stderr_to_stdout: true,
        env: [{"OPENSSL_CONF", nil}, {"OPENSSL_MODULES", nil}, {"LD_PRELOAD", nil}]
      )

    assert %{
             "status" => "passed",
             "secure_session" => true,
             "namespaces" => 3,
             "revised_ms" => revised
           } = Jason.decode!(output)

    assert revised > 0 and revised <= 60_000
  end

  test "the production native process opens a secure Session and closes it" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    parameters = Jason.decode!(File.read!(Path.join(Path.dirname(config), "native-open.json")))
    port = Port.open({:spawn_executable, executable}, [:binary, :exit_status])
    on_exit(fn -> if Port.info(port), do: Port.close(port) end)

    {ready_line, <<>>} = line(port, <<>>)
    assert {:ok, %Ready{} = ready} = Ready.decode(ready_line)
    assert {:ok, credit} = Frame.credit(1, 1, 16, 262_144)
    assert {:ok, open} = Frame.request(1, "open-1", "open", parameters, 5000, ready.clock_ms + 5000)
    assert Port.command(port, credit <> open)
    {response, <<>>} = line(port, <<>>)

    assert %{
             "version" => 1,
             "generation" => 1,
             "id" => "open-1",
             "ok" => true,
             "result" => %{
               "session_generation" => 1,
               "session_timeout_ms" => timeout,
               "namespace_array" => ["http://opcfoundation.org/UA/" | _]
             }
           } = Jason.decode!(response)

    assert timeout > 0 and timeout <= 60_000
    node_id = Jason.decode!(File.read!(config))["node_id"]

    assert {:ok, read} =
             Frame.request(
               1,
               "read-1",
               "read",
               %{"node_id" => node_id, "index_range" => nil},
               5000,
               ready.clock_ms + 10_000
             )

    assert Port.command(port, read)
    {read_response, <<>>} = line(port, <<>>)

    assert %{
             "version" => 1,
             "generation" => 1,
             "id" => "read-1",
             "ok" => true,
             "result" => %{
               "has_value" => true,
               "status" => 0,
               "value" => %{"type" => "Double", "array" => false, "value" => 21.5}
             }
           } = Jason.decode!(read_response)

    assert {:ok, close} = Frame.request(1, "close-1", "close", %{}, 5000, ready.clock_ms + 5000)
    assert Port.command(port, close)
    {close_response, <<>>} = line(port, <<>>)

    assert %{"version" => 1, "generation" => 1, "id" => "close-1", "ok" => true, "result" => nil} =
             Jason.decode!(close_response)

    assert_receive {^port, {:exit_status, 0}}, 5000
  end

  test "the BEAM owner correlates the secure open and close responses" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    parameters = Jason.decode!(File.read!(Path.join(Path.dirname(config), "native-open.json")))
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    assert {:ok, host, _} =
             Host.start_link(
               executable: executable,
               executable_digest: digest.(executable),
               guardian: guardian,
               guardian_digest: digest.(guardian),
               timeout: 5000
             )

    assert {:ok,
            %{
              "session_generation" => generation,
              "session_timeout_ms" => timeout,
              "namespace_array" => ["http://opcfoundation.org/UA/" | _]
            }} = Host.request(host, "open", parameters, 5000)

    assert is_integer(generation) and generation > 0
    assert timeout > 0 and timeout <= 60_000
    node_id = Jason.decode!(File.read!(config))["node_id"]

    assert {:ok,
            %{
              "has_value" => true,
              "status" => 0,
              "value" => %{"type" => "Double", "array" => false, "value" => 21.5}
            }} = Host.request(host, "read", %{"node_id" => node_id, "index_range" => nil}, 5000)

    assert {:ok, nil} = Host.request(host, "close", %{}, 5000)
  end

  test "a Bad read retains the remote StatusCode and ends the native generation" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    parameters = Jason.decode!(File.read!(Path.join(Path.dirname(config), "native-open.json")))
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    assert {:ok, host, _} =
             Host.start_link(
               executable: executable,
               executable_digest: digest.(executable),
               guardian: guardian,
               guardian_digest: digest.(guardian),
               timeout: 5000
             )

    assert {:ok, _} = Host.request(host, "open", parameters, 5000)

    assert {:error, %Wotex.OPCUA.Error{code: :remote_error, details: %{status: status}}} =
             Host.request(
               host,
               "read",
               %{"node_id" => "ns=2;s=missing", "index_range" => nil},
               5000
             )

    assert Bitwise.band(status, 0x8000_0000) != 0
    monitor = Process.monitor(host)
    assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000
  end

  test "a secure typed native Write is read back without retry" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    parameters = Jason.decode!(File.read!(Path.join(Path.dirname(config), "native-open.json")))
    node_id = Jason.decode!(File.read!(config))["node_id"]
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    assert {:ok, host, _} =
             Host.start_link(
               executable: executable,
               executable_digest: digest.(executable),
               guardian: guardian,
               guardian_digest: digest.(guardian),
               timeout: 5000
             )

    assert {:ok, _} = Host.request(host, "open", parameters, 5000)
    read = %{"node_id" => node_id, "index_range" => nil}

    assert {:ok, %{"value" => %{"type" => "Double", "value" => original}}} =
             Host.request(host, "read", read, 5000)

    write = fn value ->
      Host.request(
        host,
        "write",
        Map.put(read, "value", %{"type" => "Double", "array" => false, "value" => value}),
        5000
      )
    end

    assert {:ok, %{"status" => 0}} = write.(22.25)

    assert {:ok, %{"value" => %{"type" => "Double", "value" => 22.25}}} =
             Host.request(host, "read", read, 5000)

    assert {:ok, %{"status" => 0}} = write.(original)
    assert {:ok, nil} = Host.request(host, "close", %{}, 5000)
  end

  test "a rejected native Write preserves the unknown effect classification" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    parameters = Jason.decode!(File.read!(Path.join(Path.dirname(config), "native-open.json")))
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    assert {:ok, host, _} =
             Host.start_link(
               executable: executable,
               executable_digest: digest.(executable),
               guardian: guardian,
               guardian_digest: digest.(guardian),
               timeout: 5000
             )

    assert {:ok, _} = Host.request(host, "open", parameters, 5000)

    write = %{
      "node_id" => "ns=0;i=85",
      "index_range" => nil,
      "value" => %{"type" => "Double", "array" => false, "value" => 5.0}
    }

    assert {:error,
            %Wotex.OPCUA.Error{code: :remote_error, effect: :unknown, details: %{status: status}}} =
             Host.request(host, "write", write, 5000)

    assert Bitwise.band(status, 0x8000_0000) != 0
    monitor = Process.monitor(host)
    assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000
  end

  test "a secure native Call preserves ordered typed outputs and method failure effect" do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    parameters = Jason.decode!(File.read!(Path.join(Path.dirname(config), "native-open.json")))
    peer = Jason.decode!(File.read!(config))
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    assert {:ok, host, _} =
             Host.start_link(
               executable: executable,
               executable_digest: digest.(executable),
               guardian: guardian,
               guardian_digest: digest.(guardian),
               timeout: 5000
             )

    assert {:ok, _} = Host.request(host, "open", parameters, 5000)

    arguments = [
      %{"type" => "Double", "array" => false, "value" => 1.25},
      %{"type" => "Double", "array" => false, "value" => 3.25}
    ]

    call = %{
      "object_id" => peer["object_id"],
      "method_id" => peer["method_id"],
      "arguments" => arguments
    }

    assert {:ok,
            %{
              "status" => 0,
              "input_argument_statuses" => statuses,
              "outputs" => [%{"type" => "Double", "array" => false, "value" => 4.5}]
            }} =
             Host.request(host, "call", call, 5000)

    assert is_list(statuses) and Enum.all?(statuses, &(&1 == 0))

    bad = %{call | "method_id" => "ns=2;s=missing"}

    assert {:error,
            %Wotex.OPCUA.Error{code: :remote_error, effect: :unknown, details: %{status: status}}} =
             Host.request(host, "call", bad, 5000)

    assert Bitwise.band(status, 0x8000_0000) != 0
  end

  test "the public native configuration snapshots files for a secure Session" do
    config_path = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    peer = Jason.decode!(File.read!(config_path))
    directory = Path.dirname(config_path)
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    assert {:ok, config} =
             Config.new(
               executable: executable,
               executable_digest: digest.(executable),
               guardian: guardian,
               guardian_digest: digest.(guardian),
               endpoint: peer["endpoint"],
               security_policy: :basic256sha256,
               security_mode: :sign_and_encrypt,
               client_uri: peer["client_uri"],
               server_uri: peer["server_uri"],
               certificate: peer["certificate"],
               private_key: Path.join(directory, "client.key.der"),
               server_certificate: peer["server_certificate"],
               trust_certificate: Path.join(directory, "ca.der"),
               crl: peer["crl"],
               authentication: %{type: :anonymous}
             )

    assert {:ok, parameters} =
             Config.open_parameters(config, System.monotonic_time(:millisecond) + 5000)

    assert {:ok, host, _} =
             Host.start_link(
               executable: executable,
               executable_digest: digest.(executable),
               guardian: guardian,
               guardian_digest: digest.(guardian),
               timeout: 5000
             )

    assert {:ok, %{"namespace_array" => [_ | _]}} = Host.request(host, "open", parameters, 5000)
    assert {:ok, nil} = Host.request(host, "close", %{}, 5000)
  end

  test "the public native client reads, writes and calls through secure Sessions without Python" do
    peer_path = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    peer = Jason.decode!(File.read!(peer_path))
    directory = Path.dirname(peer_path)
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    options = [
      executable: executable,
      executable_digest: digest.(executable),
      guardian: guardian,
      guardian_digest: digest.(guardian),
      endpoint: peer["endpoint"],
      security_policy: :basic256sha256,
      security_mode: :sign_and_encrypt,
      client_uri: peer["client_uri"],
      server_uri: peer["server_uri"],
      certificate: peer["certificate"],
      private_key: Path.join(directory, "client.key.der"),
      server_certificate: peer["server_certificate"],
      trust_certificate: Path.join(directory, "ca.der"),
      crl: peer["crl"],
      authentication: %{type: :anonymous}
    ]

    assert {:ok, session} =
             Wotex.OPCUA.connect(Keyword.put(options, :client, Wotex.OPCUA.Open62541))

    assert {:ok, %{"value" => %{"value" => 21.5}}} =
             Wotex.OPCUA.send(session, %{type: :read, node_id: peer["node_id"]})

    write = %{type: :write, node_id: peer["node_id"], value: %{type: "Double", value: 32.5}}
    assert {:ok, %{"status" => 0}} = Wotex.OPCUA.send(session, write)

    assert {:ok, %{"value" => %{"value" => 32.5}}} =
             Wotex.OPCUA.send(session, %{type: :read, node_id: peer["node_id"]})

    assert {:ok, %{"status" => 0}} =
             Wotex.OPCUA.send(session, %{write | value: %{type: "Double", value: 21.5}})

    call = %{
      type: :call,
      node_id: peer["method_id"],
      value: %{
        object_id: peer["object_id"],
        arguments: [%{type: "Double", value: 1.25}, %{type: "Double", value: 3.25}]
      }
    }

    assert {:ok, %{"outputs" => [%{"value" => 4.5}]}} = Wotex.OPCUA.send(session, call)
    assert :ok = Wotex.OPCUA.disconnect(session)

    assert {:ok, oneshot} =
             Wotex.OPCUA.Open62541.connect(Keyword.put(options, :lifecycle, :oneshot))

    assert {:ok, %{"value" => %{"value" => 21.5}}} =
             Wotex.OPCUA.Open62541.request(
               oneshot,
               %{type: :read, node_id: peer["node_id"]},
               5000
             )

    assert :ok = Wotex.OPCUA.Open62541.disconnect(oneshot)
  end

  defp line(port, buffered) do
    case :binary.match(buffered, "\n") do
      {index, 1} ->
        size = index + 1
        {binary_part(buffered, 0, size), binary_part(buffered, size, byte_size(buffered) - size)}

      :nomatch ->
        receive do
          {^port, {:data, chunk}} -> line(port, buffered <> chunk)
          {^port, {:exit_status, code}} -> flunk("native process exited before a frame: #{code}")
        after
          5000 -> flunk("native frame timed out")
        end
    end
  end
end
