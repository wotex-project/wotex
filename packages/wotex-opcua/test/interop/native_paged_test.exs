defmodule Wotex.OPCUA.NativePagedInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Address, Browse, Error, Open62541}
  @moduletag :interop

  test "a secure C peer pages, advances, releases and collects over the wire" do
    fixture = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG") |> Path.dirname()
    peer = System.fetch_env!("WOTEX_OPCUA_PAGED_PEER")
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    assert File.regular?(peer)

    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {{127, 0, 0, 1}, port_number}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)

    port =
      Port.open({:spawn_executable, peer}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        {:args, [Integer.to_string(port_number), fixture]}
      ])

    on_exit(fn -> if Port.info(port), do: Port.close(port) end)
    assert 2 = await_ready(port, System.monotonic_time(:millisecond) + 5000)

    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    options = [
      client: Open62541,
      executable: executable,
      executable_digest: digest.(executable),
      guardian: guardian,
      guardian_digest: digest.(guardian),
      endpoint: "opc.tcp://127.0.0.1:#{port_number}",
      security_policy: :basic256sha256,
      security_mode: :sign_and_encrypt,
      client_uri: "urn:wotex:fixture:client",
      server_uri: "urn:wotex:fixture:server",
      certificate: Path.join(fixture, "client.der"),
      private_key: Path.join(fixture, "client.key.der"),
      server_certificate: Path.join(fixture, "server.der"),
      trust_certificate: Path.join(fixture, "ca.der"),
      crl: Path.join(fixture, "clean.crl"),
      authentication: %{type: :anonymous}
    ]

    object = "ns=2;s=paged"
    children = Enum.map(1..3, &"ns=2;s=child#{&1}")
    assert {:ok, session} = Wotex.OPCUA.connect(options)

    assert {:ok, %Browse.Page{status: 0, references: [first], continuation: cursor}} =
             Browse.references(session, object, page_size: 1)

    assert %Browse.Continuation{} = cursor

    assert {:ok, %Browse.Page{status: 0, references: [_], continuation: second}} =
             Browse.next(session, cursor)

    assert %Browse.Continuation{} = second
    assert :ok = Browse.release(session, second)
    assert {:error, %Error{code: :invalid_continuation}} = Browse.next(session, second)

    assert {:ok, %{status: 0, references: references}} =
             Browse.all(session, object, page_size: 1)

    assert length(references) == 3

    assert Enum.sort(Enum.map(references, &Address.to_string(&1.node_id.node_id))) ==
             children

    assert Address.to_string(first.node_id.node_id) in children
    assert {:ok, listed} = Wotex.OPCUA.send(session, %{type: :browse, node_id: object})
    assert Enum.sort(listed) == children
    assert :ok = Wotex.OPCUA.disconnect(session)

    assert {:ok, oneshot} =
             Open62541.connect(Keyword.put(Keyword.drop(options, [:client]), :lifecycle, :oneshot))

    assert {:ok, listed} = Open62541.request(oneshot, %{type: :browse, node_id: object}, 5000)
    assert Enum.sort(listed) == children
    assert :ok = Open62541.disconnect(oneshot)
  end

  defp await_ready(port, deadline) do
    timeout = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, {:eol, "READY " <> namespace}}} ->
        String.to_integer(namespace)

      {^port, {:data, _}} ->
        await_ready(port, deadline)

      {^port, {:exit_status, status}} ->
        flunk("paged peer exited before READY: #{status}")
    after
      timeout -> flunk("paged peer did not become ready")
    end
  end
end
