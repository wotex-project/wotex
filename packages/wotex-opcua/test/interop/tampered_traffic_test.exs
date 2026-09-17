defmodule Wotex.OPCUA.TamperedTrafficInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Error, Open62541, Session}
  @moduletag :interop

  setup do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    peer = Jason.decode!(File.read!(config))
    directory = Path.dirname(config)
    %URI{host: host, port: port, path: path} = URI.parse(peer["endpoint"])
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, proxy_port}} = :inet.sockname(listener)
    test = self()
    proxy = spawn_link(fn -> accept(listener, String.to_charlist(host), port, test) end)
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")

    options = [
      client: Open62541,
      executable: executable,
      executable_digest: digest(executable),
      guardian: guardian,
      guardian_digest: digest(guardian),
      endpoint: "opc.tcp://127.0.0.1:#{proxy_port}#{path}",
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

    %{peer: peer, options: options, proxy: proxy}
  end

  test "WOP-V09 a tampered response chunk fails the Read without a forged value", context do
    %{peer: peer} = context
    assert {:ok, session} = Wotex.OPCUA.connect(context.options)
    %Session{handle: %{host: host}} = session
    processes = native_processes(host)
    read = %{type: :read, node_id: peer["node_id"]}
    assert {:ok, %{"value" => %{"value" => value}}} = Wotex.OPCUA.send(session, read)
    assert is_float(value)
    send(context.proxy, {:tamper, :flip})

    assert {:error, %Error{effect: :none} = error} = Wotex.OPCUA.send(session, read)
    assert error.code in [:connection_failed, :invalid_response]
    assert_receive {:tampered, :flip}
    assert eventually(fn -> not Process.alive?(host) end, 1000)
    assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end, 1000)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-V09 a replayed response chunk ends the Session without a stale value", context do
    %{peer: peer} = context
    assert {:ok, session} = Wotex.OPCUA.connect(context.options)
    %Session{handle: %{host: host}} = session
    processes = native_processes(host)
    read = %{type: :read, node_id: peer["node_id"]}
    assert {:ok, %{"value" => %{"value" => original}}} = Wotex.OPCUA.send(session, read)
    send(context.proxy, {:tamper, :replay})

    assert {:error, %Error{effect: :none} = error} = Wotex.OPCUA.send(session, read)
    assert error.code in [:connection_failed, :invalid_response]
    assert_receive {:tampered, :replay}
    assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end, 1000)

    assert {:ok, second} = connect_direct(context)
    assert {:ok, %{"value" => %{"value" => ^original}}} = Wotex.OPCUA.send(second, read)
    assert :ok = Wotex.OPCUA.disconnect(second)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-V09 a tampered Write response keeps an unknown effect", context do
    %{peer: peer} = context
    assert {:ok, session} = Wotex.OPCUA.connect(context.options)
    %Session{handle: %{host: host}} = session
    read = %{type: :read, node_id: peer["node_id"]}
    assert {:ok, %{"value" => %{"value" => original}}} = Wotex.OPCUA.send(session, read)
    send(context.proxy, {:tamper, :flip})

    write = %{type: :write, node_id: peer["node_id"], value: %{type: "Double", value: 61.5}}
    assert {:error, %Error{effect: :unknown}} = Wotex.OPCUA.send(session, write)
    assert_receive {:tampered, :flip}
    assert eventually(fn -> not Process.alive?(host) end, 1000)

    assert {:ok, direct} = connect_direct(context)

    assert {:ok, %{"status" => 0}} =
             Wotex.OPCUA.send(direct, %{write | value: %{type: "Double", value: original}})

    assert :ok = Wotex.OPCUA.disconnect(direct)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  defp connect_direct(context),
    do: Wotex.OPCUA.connect(Keyword.put(context.options, :endpoint, context.peer["endpoint"]))

  defp accept(listener, host, port, test) do
    {:ok, client} = :gen_tcp.accept(listener)
    {:ok, server} = :gen_tcp.connect(host, port, [:binary, active: false])
    parent = self()
    spawn_link(fn -> pump(client, server) end)
    downstream = spawn_link(fn -> relay(server, client, <<>>, {nil, nil}, parent) end)
    control(downstream, test)
  end

  defp control(downstream, test) do
    receive do
      {:tamper, mode} ->
        send(downstream, {:tamper, mode})
        control(downstream, test)

      {:tampered, info} ->
        send(test, {:tampered, info})
        control(downstream, test)
    end
  end

  defp pump(from, to) do
    case :gen_tcp.recv(from, 0) do
      {:ok, bytes} ->
        :ok = :gen_tcp.send(to, bytes)
        pump(from, to)

      _ ->
        :gen_tcp.close(to)
    end
  end

  # Relays whole OPC UA TCP chunks from the server. On request it flips the last
  # byte of the next MSG chunk or sends the previous MSG chunk again before it.
  defp relay(from, to, buffer, {mode, previous}, parent) do
    mode =
      receive do
        {:tamper, requested} -> requested
      after
        0 -> mode
      end

    case buffer do
      <<_::binary-size(4), size::little-32, _::binary>> when byte_size(buffer) >= size ->
        <<chunk::binary-size(^size), rest::binary>> = buffer
        {frames, state} = alter(chunk, mode, previous, parent)
        Enum.each(frames, &(:ok = :gen_tcp.send(to, &1)))
        relay(from, to, rest, state, parent)

      _ ->
        case :gen_tcp.recv(from, 0, 50) do
          {:ok, bytes} -> relay(from, to, buffer <> bytes, {mode, previous}, parent)
          {:error, :timeout} -> relay(from, to, buffer, {mode, previous}, parent)
          _ -> :gen_tcp.close(to)
        end
    end
  end

  defp alter(<<"MSG", _::binary>> = chunk, :flip, _, parent) do
    position = byte_size(chunk) - 1
    <<head::binary-size(^position), last>> = chunk
    send(parent, {:tampered, :flip})
    {[<<head::binary, Bitwise.bxor(last, 0xFF)>>], {nil, chunk}}
  end

  defp alter(<<"MSG", _::binary>> = chunk, :replay, previous, parent) when is_binary(previous) do
    send(parent, {:tampered, :replay})
    {[previous, chunk], {nil, chunk}}
  end

  defp alter(<<"MSG", _::binary>> = chunk, mode, _, _), do: {[chunk], {mode, chunk}}
  defp alter(chunk, mode, previous, _), do: {[chunk], {mode, previous}}

  defp native_processes(host) do
    %{port: port} = :sys.get_state(host)
    {:os_pid, guardian} = Port.info(port, :os_pid)

    {children, 0} =
      System.cmd("/usr/bin/pgrep", ["-P", Integer.to_string(guardian)], env: [{"LC_ALL", "C"}])

    [guardian | Enum.map(String.split(children), &String.to_integer/1)]
  end

  defp os_alive?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: [{"LC_ALL", "C"}]
      )

    status == 0
  end

  defp eventually(check, budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    poll(check, deadline)
  end

  defp poll(check, deadline) do
    cond do
      check.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        poll(check, deadline)
    end
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
