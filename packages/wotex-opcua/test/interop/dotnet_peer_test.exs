defmodule Wotex.OPCUA.DotnetPeerInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Address, Browse, Error, Open62541}
  @moduletag :interop

  # The second independent peer runs the OPC Foundation UA-.NETStandard server.
  # Its fixture methods report the server's own live browse continuation points
  # across every Session and the number of requests its Cancel service found.
  setup do
    peer = Jason.decode!(File.read!(System.fetch_env!("WOTEX_OPCUA_DOTNET_CONFIG")))
    fixture = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG") |> Path.dirname()
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    options = [
      client: Open62541,
      executable: executable,
      executable_digest: digest.(executable),
      guardian: guardian,
      guardian_digest: digest.(guardian),
      endpoint: peer["endpoint"],
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

    assert {:ok, session} = Wotex.OPCUA.connect(options)
    on_exit(fn -> Wotex.OPCUA.disconnect(session) end)

    assert {:ok, %{"value" => %{"type" => "String", "array" => true, "value" => namespaces}}} =
             Wotex.OPCUA.send(session, %{type: :read, node_id: "i=2255"})

    index = Enum.find_index(namespaces, &(&1 == peer["namespace_uri"]))
    assert is_integer(index)
    node = &Address.to_string(%Address{namespace: index, kind: :string, identifier: &1})

    %{session: session, peer: peer, node: node}
  end

  test "WOP-N03 WOP-N04 the independent server counts every continuation the client holds",
       %{session: session, peer: peer, node: node} do
    paged = node.("paged")
    children = for index <- 1..peer["children"], do: node.("child#{index}")
    live = fn -> count(session, node, "continuation_points") end
    assert live.() == 0

    assert {:ok, %Browse.Page{status: 0, references: first, continuation: cursor}} =
             Browse.references(session, paged, page_size: 5)

    assert length(first) == 5
    assert %Browse.Continuation{} = cursor
    assert live.() == 1

    assert {:ok, %Browse.Page{status: 0, references: second, continuation: next}} =
             Browse.next(session, cursor)

    assert length(second) == 5
    assert live.() == 1
    assert :ok = Browse.release(session, next)
    assert live.() == 0
    assert {:error, %Error{code: :invalid_continuation}} = Browse.next(session, next)
    assert {:error, %Error{code: :invalid_continuation}} = Browse.next(session, cursor)

    assert {:ok, %{status: 0, references: references}} = Browse.all(session, paged, page_size: 7)
    assert Enum.map(references, &Address.to_string(&1.node_id.node_id)) == children

    assert Enum.map(first ++ second, &Address.to_string(&1.node_id.node_id)) ==
             Enum.take(children, 10)

    assert live.() == 0

    assert {:ok, %Browse.Page{continuation: left}} =
             Browse.references(session, paged, page_size: 5)

    assert {:ok, %Browse.Page{continuation: right}} =
             Browse.references(session, paged, page_size: 5)

    assert live.() == 2
    assert :ok = Browse.release(session, left)
    assert live.() == 1

    assert {:ok, %Browse.Page{references: [_ | _], continuation: after_right}} =
             Browse.next(session, right)

    assert live.() == 1
    assert :ok = Browse.release(session, after_right)
    assert live.() == 0

    assert {:ok, listed} = Wotex.OPCUA.send(session, %{type: :browse, node_id: paged})
    assert listed == children
    assert live.() == 0
  end

  test "WOP-N04 limit failures and an expired browse deadline release the server continuation",
       %{session: session, node: node} do
    paged = node.("paged")
    live = fn -> count(session, node, "continuation_points") end

    assert {:error, %Error{code: :response_limit, effect: :none}} =
             Browse.all(session, paged, page_size: 5, max_references: 12)

    assert live.() == 0

    assert {:error, %Error{code: :response_limit, effect: :none}} =
             Browse.all(session, paged, page_size: 5, max_pages: 2)

    assert live.() == 0

    assert {:ok, %Browse.Page{continuation: expiring}} =
             Browse.references(session, paged, page_size: 5, timeout_ms: 200)

    assert live.() == 1
    assert eventually(fn -> live.() == 0 end)
    assert {:error, %Error{code: :deadline_exceeded}} = Browse.next(session, expiring)
  end

  test "WOP-C03 an expired or abandoned Call reaches the server's Cancel service",
       %{session: session, node: node} do
    cancelled = fn -> count(session, node, "cancel_count") end
    before = cancelled.()
    started = System.monotonic_time(:millisecond)
    slow = slow(node, 1500)

    assert {:error, %Error{code: :deadline_exceeded, effect: :unknown}} =
             Wotex.OPCUA.send(%{session | timeout: 300}, slow)

    assert eventually(fn -> cancelled.() == before + 1 end)

    caller = spawn(fn -> Wotex.OPCUA.send(session, slow) end)
    Process.sleep(200)
    Process.exit(caller, :kill)
    assert eventually(fn -> cancelled.() == before + 2 end)

    # Both late Call responses arrive after their Cancel; the Session discards
    # them and keeps serving.
    Process.sleep(max(started + 2500 - System.monotonic_time(:millisecond), 0))

    assert {:ok, %{"outputs" => [%{"type" => "UInt32", "value" => 1}]}} =
             Wotex.OPCUA.send(session, slow(node, 1))

    assert cancelled.() == before + 2
  end

  defp count(session, node, method) do
    assert {:ok, %{"outputs" => [%{"type" => "UInt32", "value" => value}]}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: node.(method),
               value: %{object_id: node.("fixture"), arguments: []}
             })

    value
  end

  defp slow(node, milliseconds) do
    %{
      type: :call,
      node_id: node.("slow"),
      value: %{object_id: node.("fixture"), arguments: [%{type: "UInt32", value: milliseconds}]}
    }
  end

  defp eventually(check, attempts \\ 100) do
    cond do
      check.() -> true
      attempts == 0 -> false
      true -> Process.sleep(50) && eventually(check, attempts - 1)
    end
  end
end
