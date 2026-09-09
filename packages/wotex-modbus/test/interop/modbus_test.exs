defmodule Wotex.Modbus.InteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Modbus
  alias Wotex.Modbus.{Command, RuntimeFixture, Transport}
  alias Wotex.Runtime.{ConsumedThing, Context, Result}
  @moduletag :interop

  test "WMB-S01 WMB-S02 WMB-S04 WMB-V11 independent libmodbus confirms every advertised function and exception" do
    host = System.fetch_env!("WOTEX_MODBUS_INTEROP_HOST")
    port = System.fetch_env!("WOTEX_MODBUS_INTEROP_PORT") |> String.to_integer()
    assert {:ok, conn} = Modbus.connect(host: host, port: port, unit_id: 1, timeout: 1000)

    try do
      assert {:ok, [42]} = Modbus.read_holding_registers(conn, 0, 1)
      assert {:ok, [77]} = Modbus.read_input_registers(conn, 0, 1)
      assert {:ok, [true]} = Modbus.read_discrete_inputs(conn, 0, 1)
      assert :ok = Modbus.write_holding_register(conn, 10, 1234)
      assert {:ok, [1234]} = Modbus.read_holding_registers(conn, 10, 1)
      assert :ok = Modbus.write_holding_registers(conn, 11, [0, 65_535, 7])
      assert {:ok, [0, 65_535, 7]} = Modbus.read_holding_registers(conn, 11, 3)
      assert :ok = Modbus.write_coil(conn, 0, true)
      assert {:ok, [true]} = Modbus.read_coils(conn, 0, 1)

      assert :ok =
               Modbus.write_coils(conn, 1, [
                 false,
                 true,
                 false,
                 true,
                 true,
                 false,
                 false,
                 true,
                 true
               ])

      assert {:ok, [false, true, false, true, true, false, false, true, true]} =
               Modbus.read_coils(conn, 1, 9)

      assert :ok = Modbus.write_float(conn, 20, 23.5)
      assert {:ok, 23.5} = Modbus.read_float(conn, 20)

      assert {:error, %{code: :remote_exception, details: %{exception_code: 2}}} =
               Modbus.read_holding_registers(conn, 400, 1)

      assert {:ok, :healthy} = Modbus.health_check(conn)
    after
      assert :ok = Modbus.disconnect(conn)
    end
  end

  test "WMB-D01 WMB-D02 WMB-D03 WMB-I01 WMB-I03 WMB-I06 standalone and Runtime workflows use the independent peer" do
    host = System.fetch_env!("WOTEX_MODBUS_INTEROP_HOST")
    port = String.to_integer(System.fetch_env!("WOTEX_MODBUS_INTEROP_PORT"))
    {:ok, session} = Modbus.connect(host: host, port: port)

    try do
      assert :ok = Modbus.write_float(session, 40, 25.5)
      assert {:ok, [16_844, 0]} = Modbus.read_holding_registers(session, 40, 2)
      assert {:ok, 25.5} = Modbus.read_float(session, 40)
      {:ok, probe} = Command.new(:read_holding_registers, 40, 1)
      assert {:ok, :healthy} = Modbus.health_check(session, probe)
    after
      assert :ok = Modbus.disconnect(session)
    end

    form = %{
      "href" => "modbus+tcp://#{host}:#{port}/1/41?quantity=2",
      "modv:entity" => "HoldingRegister",
      "modv:type" => "xsd:float"
    }

    consumed = RuntimeFixture.consumed(RuntimeFixture.td(form), {Transport, []})
    {:ok, context} = Context.new(request_id: "independent-read")

    assert {:ok,
            %Result{
              request_id: "independent-read",
              payload: 25.5,
              status: :ok,
              metadata: %{function: 3}
            }} = ConsumedThing.read_property(consumed, "reading", context)

    assert {:ok, %Result{operation: :writeproperty, payload: :written, status: :ok}} =
             ConsumedThing.write_property(consumed, "reading", -1.5, context)

    assert {:ok, %Result{payload: -1.5}} = ConsumedThing.read_property(consumed, "reading", context)
    action = %{"href" => "modbus+tcp://#{host}:#{port}/1/61", "modv:function" => "writeSingleCoil"}

    description =
      RuntimeFixture.td(form)
      |> Map.put("actions", %{"switch" => %{"forms" => [action]}})

    consumed = RuntimeFixture.consumed(description, {Transport, []})

    assert {:ok, %Result{operation: :invokeaction, payload: :written, metadata: %{function: 5}}} =
             ConsumedThing.invoke_action(consumed, "switch", false, context)
  end
end
