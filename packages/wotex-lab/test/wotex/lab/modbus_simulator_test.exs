defmodule Wotex.Lab.ModbusSimulatorTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Test.ModbusSimulator
  alias Wotex.Modbus
  alias Wotex.Modbus.Error
  alias Wotex.Runtime.{ConsumedThing, Context, Result}

  @moduletag :simulator
  @moduletag timeout: 180_000

  setup_all do
    %{image: ModbusSimulator.prepare()}
  end

  setup %{image: image} do
    peer = ModbusSimulator.start(image)
    %{peer: peer, session: ModbusSimulator.connect(peer)}
  end

  test "the independent server exposes separate register and bit tables", %{session: session} do
    assert {:ok, [0x41AC, 0, 0x43D2, 0]} = Modbus.read_input_registers(session, 0, 4)
    assert {:ok, [0x41A8, 0]} = Modbus.read_holding_registers(session, 0, 2)
    assert {:ok, [false, false]} = Modbus.read_coils(session, 0, 2)
    assert {:ok, [true, false]} = Modbus.read_discrete_inputs(session, 0, 2)
  end

  test "single and multiple writes preserve the measured input registers", %{session: session} do
    assert :ok = Modbus.write_holding_register(session, 8, 42)
    assert {:ok, [42]} = Modbus.read_holding_registers(session, 8, 1)
    assert :ok = Modbus.write_holding_registers(session, 8, [7, 8, 9])
    assert {:ok, [7, 8, 9]} = Modbus.read_holding_registers(session, 8, 3)
    assert :ok = Modbus.write_coil(session, 0, true)
    assert {:ok, [true, false]} = Modbus.read_coils(session, 0, 2)
    bits = [true, false, true, false, true, false, true, false, true]
    assert :ok = Modbus.write_coils(session, 0, bits)
    assert {:ok, ^bits} = Modbus.read_coils(session, 0, 9)
    assert {:ok, [0x41AC, 0]} = Modbus.read_input_registers(session, 0, 2)
  end

  test "Runtime reads and writes the typed Thing through the real peer", %{peer: peer} do
    consumed = ModbusSimulator.consumed(peer)
    context = Context.new!(request_id: "simulated-zone")

    assert {:ok, %Result{payload: 21.5}} =
             ConsumedThing.read_property(consumed, "temperature", context)

    assert {:ok, %Result{payload: 420.0}} = ConsumedThing.read_property(consumed, "power", context)
    assert {:ok, %Result{payload: 21.0}} = ConsumedThing.read_property(consumed, "target", context)

    assert {:ok, %Result{payload: :written}} =
             ConsumedThing.write_property(consumed, "target", 23.5, context)

    assert {:ok, %Result{payload: 23.5}} = ConsumedThing.read_property(consumed, "target", context)

    assert {:ok, %Result{operation: :invokeaction, payload: :written}} =
             ConsumedThing.invoke_action(consumed, "setTarget", 20.5, context)

    assert {:ok, %Result{payload: 20.5}} = ConsumedThing.read_property(consumed, "target", context)

    assert {:ok, %Result{payload: 21.5}} =
             ConsumedThing.read_property(consumed, "temperature", context)
  end

  test "a peer exception is typed and does not poison the next exchange", %{session: session} do
    assert {:error, %Error{code: :remote_exception, effect: :none}} =
             Modbus.read_holding_registers(session, 100, 1)

    assert {:ok, [0x41A8, 0]} = Modbus.read_holding_registers(session, 0, 2)
  end

  test "the last register is usable but an exchange crossing the table fails atomically", %{
    session: session
  } do
    assert :ok = Modbus.write_holding_register(session, 15, 123)
    assert {:ok, [123]} = Modbus.read_holding_registers(session, 15, 1)

    assert {:error, %Error{code: :remote_exception, effect: :none}} =
             Modbus.read_holding_registers(session, 15, 2)

    assert {:error, %Error{code: :remote_exception}} =
             Modbus.write_holding_registers(session, 15, [456, 789])

    assert {:ok, [123]} = Modbus.read_holding_registers(session, 15, 1)
  end

  test "device state survives a client reconnect while a fresh device restores the model", %{
    image: image,
    peer: peer,
    session: session
  } do
    assert :ok = Modbus.write_holding_register(session, 8, 321)
    assert :ok = Modbus.disconnect(session)
    refute Process.alive?(session.pid)

    reconnected = ModbusSimulator.connect(peer)
    assert {:ok, [321]} = Modbus.read_holding_registers(reconnected, 8, 1)

    fresh =
      image
      |> ModbusSimulator.start()
      |> ModbusSimulator.connect()

    assert {:ok, [0]} = Modbus.read_holding_registers(fresh, 8, 1)
  end

  test "two simulated devices retain independent command state", %{image: image, session: first} do
    second_peer = ModbusSimulator.start(image)
    second = ModbusSimulator.connect(second_peer)
    assert :ok = Modbus.write_holding_register(first, 8, 99)
    assert {:ok, [99]} = Modbus.read_holding_registers(first, 8, 1)
    assert {:ok, [0]} = Modbus.read_holding_registers(second, 8, 1)
  end

  test "peer shutdown closes the exchange and the connection owner can clean up", %{
    peer: peer,
    session: session
  } do
    assert :ok = ModbusSimulator.stop(peer)
    assert {:error, %Error{effect: :none}} = Modbus.read_input_registers(session, 0, 1)
    assert :ok = Modbus.disconnect(session)
    refute Process.alive?(session.pid)
  end
end
