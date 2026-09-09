defmodule Wotex.BLE.PortTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Wotex.BLE
  alias Wotex.BLE.{Error, TestClient}
  @read %{type: :read, service: 0x180F, characteristic: 0x2A19}

  test "explicit client requests and cleanup preserve contract without implicit transports" do
    assert {:error, %Error{}} = BLE.connect([])
    assert {:error, _} = BLE.connect(nil)
    assert {:error, _} = BLE.connect([:invalid])
    assert {:error, _} = BLE.connect(client: TestClient, timeout: 0)
    assert {:error, _} = BLE.connect(client: TestClient, mode: :connect_error)
    assert {:error, _} = BLE.connect(client: MissingClient)
    assert {:ok, conn} = BLE.connect(client: TestClient)
    refute inspect(conn) =~ "fixture-secret"
    assert {:ok, @read} = BLE.send(conn, @read)
    assert :ok = BLE.disconnect(conn)
    assert :ok = BLE.disconnect(conn)
    assert_receive :disconnected
    assert_receive :disconnected
    assert {:error, _} = BLE.send(conn, %{})
    assert {:error, _} = BLE.receive(conn, 100)
    assert {:error, _} = BLE.health_check(conn)
    assert {:error, %{code: :not_supported}} = BLE.subscribe(conn, "value")
    assert {:error, %{code: :not_supported}} = BLE.unsubscribe(conn, :ref)
    assert BLE.capabilities().transport == :explicit_client

    assert BLE.with_connection([client: TestClient], fn session -> BLE.send(session, @read) end) ==
             {:ok, @read}

    assert_receive :disconnected

    assert_raise RuntimeError, fn ->
      BLE.with_connection([client: TestClient], fn _ -> raise "test" end)
    end

    assert_receive :disconnected
  end

  test "port failures are credential-free structured errors" do
    for mode <- [:raise, :throw, :exit, :error, :typed, :invalid] do
      {:ok, conn} = BLE.connect(client: TestClient, mode: mode)
      assert {:error, %Error{} = error} = BLE.send(conn, @read)
      refute inspect(error) =~ "private"
      BLE.disconnect(conn)
    end

    for mode <- [:close_error, :close_invalid] do
      {:ok, conn} = BLE.connect(client: TestClient, mode: mode)
      assert {:error, %Error{}} = BLE.disconnect(conn)
    end
  end

  test "failed writes have unknown effect and invalid addresses never reach the port" do
    {:ok, conn} = BLE.connect(client: TestClient, mode: :error)

    assert {:error, %{effect: :unknown}} =
             BLE.send(conn, %{type: :write, service: 0x180F, characteristic: 0x2A19, value: <<42>>})

    assert {:error, %{effect: :none}} = BLE.send(conn, %{type: :read})
    BLE.disconnect(conn)
  end
end
