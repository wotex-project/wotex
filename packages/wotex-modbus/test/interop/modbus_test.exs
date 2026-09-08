defmodule Wotex.Modbus.InteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Modbus
  @moduletag :interop

  test "independent libmodbus peer confirms every advertised function and exception" do
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
end
