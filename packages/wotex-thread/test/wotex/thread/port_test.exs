defmodule Wotex.Thread.PortTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread
  alias Wotex.Thread.{Error, TestClient}
  @read %{type: :state}

  test "explicit client requests and cleanup preserve contract without implicit transports" do
    assert {:error, %Error{}} = Thread.connect([])
    assert {:error, _} = Thread.connect(nil)
    assert {:error, _} = Thread.connect([:invalid])
    assert {:error, _} = Thread.connect(client: TestClient, timeout: 0)
    assert {:error, _} = Thread.connect(client: TestClient, mode: :connect_error)
    assert {:error, _} = Thread.connect(client: MissingClient)
    assert {:ok, conn} = Thread.connect(client: TestClient)
    refute inspect(conn) =~ "fixture-secret"
    assert {:ok, @read} = Thread.send(conn, @read)
    assert :ok = Thread.disconnect(conn)
    assert :ok = Thread.disconnect(conn)
    assert_receive :disconnected
    assert_receive :disconnected
    assert {:error, _} = Thread.send(conn, %{})
    assert {:error, _} = Thread.receive(conn, 100)
    assert {:error, _} = Thread.health_check(conn)
    assert :not_supported = Thread.subscribe(conn, "value")
    assert :not_supported = Thread.unsubscribe(conn, :ref)
    assert Thread.capabilities().transport == :explicit_client

    assert Thread.with_connection([client: TestClient], fn session ->
             Thread.send(session, @read)
           end) == {:ok, @read}

    assert_receive :disconnected

    assert_raise RuntimeError, fn ->
      Thread.with_connection([client: TestClient], fn _ -> raise "test" end)
    end

    assert_receive :disconnected
  end

  test "port failures are credential-free structured errors" do
    for mode <- [:raise, :throw, :exit, :error, :typed, :invalid] do
      {:ok, conn} = Thread.connect(client: TestClient, mode: mode)
      assert {:error, %Error{} = error} = Thread.send(conn, @read)
      refute inspect(error) =~ "private"
      Thread.disconnect(conn)
    end

    for mode <- [:close_error, :close_invalid] do
      {:ok, conn} = Thread.connect(client: TestClient, mode: mode)
      assert {:error, %Error{}} = Thread.disconnect(conn)
    end
  end
end
