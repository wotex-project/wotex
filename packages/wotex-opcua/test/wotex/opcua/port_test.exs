defmodule Wotex.OPCUA.PortTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA
  alias Wotex.OPCUA.{Error, Subscription, TestClient}
  @read %{type: :read, node_id: "ns=2;s=Temperature"}

  defmodule SubscribingClient do
    @moduledoc false

    @behaviour Wotex.OPCUA.Client

    @impl Wotex.OPCUA.Client
    def connect(opts), do: {:ok, Keyword.fetch!(opts, :reply)}

    @impl Wotex.OPCUA.Client
    def request(_, _, _), do: {:error, Wotex.OPCUA.Error.new(:not_supported)}

    @impl Wotex.OPCUA.Client
    def disconnect(_), do: :ok

    @impl Wotex.OPCUA.Client
    def subscribe(reply, _, _, _), do: reply

    @impl Wotex.OPCUA.Client
    def unsubscribe(reply, _, _), do: reply
  end

  test "explicit client requests and cleanup preserve contract without implicit transports" do
    assert {:error, %Error{}} = OPCUA.connect([])
    assert {:error, _} = OPCUA.connect(nil)
    assert {:error, _} = OPCUA.connect([:invalid])
    assert {:error, _} = OPCUA.connect(client: TestClient, timeout: 0)
    assert {:error, _} = OPCUA.connect(client: TestClient, mode: :connect_error)
    assert {:error, _} = OPCUA.connect(client: MissingClient)
    assert {:ok, conn} = OPCUA.connect(client: TestClient)
    refute inspect(conn) =~ "fixture-secret"
    assert {:ok, @read} = OPCUA.send(conn, @read)
    assert :ok = OPCUA.disconnect(conn)
    assert :ok = OPCUA.disconnect(conn)
    assert_receive :disconnected
    assert_receive :disconnected
    assert {:error, _} = OPCUA.send(conn, %{})
    assert {:error, _} = OPCUA.receive(conn, 100)
    assert {:error, _} = OPCUA.health_check(conn)
    assert :not_supported = OPCUA.subscribe(conn, "value")
    assert :not_supported = OPCUA.unsubscribe(conn, :ref)
    assert OPCUA.capabilities().transport == :explicit_client

    assert OPCUA.with_connection([client: TestClient], fn session -> OPCUA.send(session, @read) end) ==
             {:ok, @read}

    assert_receive :disconnected

    assert_raise RuntimeError, fn ->
      OPCUA.with_connection([client: TestClient], fn _ -> raise "test" end)
    end

    assert_receive :disconnected
  end

  test "port failures are credential-free structured errors" do
    for mode <- [:raise, :throw, :exit, :error, :typed, :invalid] do
      {:ok, conn} = OPCUA.connect(client: TestClient, mode: mode)
      assert {:error, %Error{} = error} = OPCUA.send(conn, @read)
      refute inspect(error) =~ "private"
      OPCUA.disconnect(conn)
    end

    for mode <- [:close_error, :close_invalid] do
      {:ok, conn} = OPCUA.connect(client: TestClient, mode: mode)
      assert {:error, %Error{}} = OPCUA.disconnect(conn)
    end
  end

  test "WOP-S04 subscription callbacks keep only typed client returns" do
    handle = %Subscription{pid: self(), reference: make_ref(), generation: 1}
    request = %{node_id: "ns=2;s=Temperature"}

    for {reply, subscribed, unsubscribed} <- [
          {{:ok, handle}, {:ok, handle}, {:error, :invalid_transport_return}},
          {{:ok, :unexpected}, {:error, :invalid_transport_return},
           {:error, :invalid_transport_return}},
          {:ok, {:error, :invalid_transport_return}, :ok},
          {{:error, :private}, {:error, :transport_error}, {:error, :transport_error}}
        ] do
      {:ok, conn} = OPCUA.connect(client: SubscribingClient, reply: reply)
      assert normalize(OPCUA.subscribe(conn, request)) == subscribed
      assert normalize(OPCUA.unsubscribe(conn, handle)) == unsubscribed
    end

    {:ok, conn} = OPCUA.connect(client: SubscribingClient, reply: {:ok, handle})

    for invalid <- [%{node_id: "ns=2;s=Temperature", publishing_interval_ms: "10"}, "value"] do
      assert {:error, %Error{code: :invalid_value}} = OPCUA.subscribe(conn, invalid)
    end

    assert {:error, %Error{code: :invalid_subscription}} = OPCUA.unsubscribe(conn, :ref)
  end

  test "failed writes have unknown effect and invalid addresses never reach the port" do
    {:ok, conn} = OPCUA.connect(client: TestClient, mode: :error)

    assert {:error, %{effect: :unknown}} =
             OPCUA.send(conn, %{type: :write, node_id: "ns=2;s=Temperature", value: 1.5})

    assert {:error, %{effect: :none}} = OPCUA.send(conn, %{type: :read})
    OPCUA.disconnect(conn)
  end

  defp normalize({:error, %Error{code: code}}), do: {:error, code}
  defp normalize(result), do: result
end
