defmodule Wotex.Matter.PortTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Wotex.Matter
  alias Wotex.Matter.{Error, TestClient}
  @read %{type: :read, fabric_id: 1, node_id: 1, endpoint: 1, cluster: 6, member: 0}

  test "explicit client requests and cleanup preserve contract without implicit transports" do
    assert {:error, %Error{}} = Matter.connect([])
    assert {:error, _} = Matter.connect(nil)
    assert {:error, _} = Matter.connect([:invalid])
    assert {:error, _} = Matter.connect(client: TestClient, timeout: 0)
    assert {:error, _} = Matter.connect(client: TestClient, mode: :connect_error)
    assert {:error, _} = Matter.connect(client: MissingClient)
    assert {:ok, conn} = Matter.connect(client: TestClient)
    refute inspect(conn) =~ "fixture-secret"
    assert {:ok, @read} = Matter.send(conn, @read)
    assert :ok = Matter.disconnect(conn)
    assert :ok = Matter.disconnect(conn)
    assert_receive :disconnected
    assert_receive :disconnected
    assert {:error, _} = Matter.send(conn, %{})
    assert {:error, _} = Matter.receive(conn, 100)
    assert {:error, _} = Matter.health_check(conn)
    assert :not_supported = Matter.subscribe(conn, "value")
    assert :not_supported = Matter.unsubscribe(conn, :ref)
    assert Matter.capabilities().transport == :explicit_client

    assert Matter.with_connection([client: TestClient], fn session ->
             Matter.send(session, @read)
           end) == {:ok, @read}

    assert_receive :disconnected

    assert_raise RuntimeError, fn ->
      Matter.with_connection([client: TestClient], fn _ -> raise "test" end)
    end

    assert_receive :disconnected
  end

  test "port failures are credential-free structured errors" do
    for mode <- [:raise, :throw, :exit, :error, :typed, :invalid] do
      {:ok, conn} = Matter.connect(client: TestClient, mode: mode)
      assert {:error, %Error{} = error} = Matter.send(conn, @read)
      refute inspect(error) =~ "private"
      Matter.disconnect(conn)
    end

    for mode <- [:close_error, :close_invalid] do
      {:ok, conn} = Matter.connect(client: TestClient, mode: mode)
      assert {:error, %Error{}} = Matter.disconnect(conn)
    end
  end

  test "failed writes have unknown effect and invalid addresses never reach the port" do
    {:ok, conn} = Matter.connect(client: TestClient, mode: :error)

    assert {:error, %{effect: :unknown}} =
             Matter.send(conn, %{
               type: :write,
               fabric_id: 1,
               node_id: 1,
               endpoint: 1,
               cluster: 6,
               member: 0,
               value: true
             })

    assert {:error, %{effect: :none}} = Matter.send(conn, %{type: :read})
    Matter.disconnect(conn)
  end
end
