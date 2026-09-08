defmodule Wotex.BACnet.PortTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Wotex.BACnet
  alias Wotex.BACnet.{Error, TestClient}
  @read %{type: :read_property, object_type: :analog_input, instance: 1, property: :present_value}

  test "explicit client requests and cleanup preserve contract without implicit transports" do
    assert {:error, %Error{}} = BACnet.connect([])
    assert {:error, _} = BACnet.connect(nil)
    assert {:error, _} = BACnet.connect([:invalid])
    assert {:error, _} = BACnet.connect(client: TestClient, timeout: 0)
    assert {:error, _} = BACnet.connect(client: TestClient, mode: :connect_error)
    assert {:error, _} = BACnet.connect(client: MissingClient)
    assert {:ok, conn} = BACnet.connect(client: TestClient)
    refute inspect(conn) =~ "fixture-secret"
    assert {:ok, @read} = BACnet.send(conn, @read)
    assert :ok = BACnet.disconnect(conn)
    assert :ok = BACnet.disconnect(conn)
    assert_receive :disconnected
    assert_receive :disconnected
    assert {:error, _} = BACnet.send(conn, %{})
    assert {:error, _} = BACnet.receive(conn, 100)
    assert {:error, _} = BACnet.health_check(conn)
    assert :not_supported = BACnet.subscribe(conn, "value")
    assert :not_supported = BACnet.unsubscribe(conn, :ref)
    assert BACnet.capabilities().transport == :explicit_client

    assert BACnet.with_connection([client: TestClient], fn session ->
             BACnet.send(session, @read)
           end) == {:ok, @read}

    assert_receive :disconnected

    assert_raise RuntimeError, fn ->
      BACnet.with_connection([client: TestClient], fn _ -> raise "test" end)
    end

    assert_receive :disconnected
  end

  test "port failures are credential-free structured errors" do
    for mode <- [:raise, :throw, :exit, :error, :typed, :invalid] do
      {:ok, conn} = BACnet.connect(client: TestClient, mode: mode)
      assert {:error, %Error{} = error} = BACnet.send(conn, @read)
      refute inspect(error) =~ "private"
      BACnet.disconnect(conn)
    end

    for mode <- [:close_error, :close_invalid] do
      {:ok, conn} = BACnet.connect(client: TestClient, mode: mode)
      assert {:error, %Error{}} = BACnet.disconnect(conn)
    end
  end

  test "failed writes have unknown effect and invalid addresses never reach the port" do
    {:ok, conn} = BACnet.connect(client: TestClient, mode: :error)

    assert {:error, %{effect: :unknown}} =
             BACnet.send(conn, %{
               type: :write_property,
               object_type: :analog_output,
               instance: 1,
               property: :present_value,
               value: 1.5
             })

    assert {:error, %{effect: :none}} = BACnet.send(conn, %{type: :read_property})
    BACnet.disconnect(conn)
  end
end
