defmodule Wotex.Modbus.ConnectionTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Modbus
  alias Wotex.Modbus.{Command, Connection, Error, TestPeer}

  test "WMB-D01 WMB-D02 all helpers and compatibility operations use correlated TCP responses" do
    {peer, port} =
      TestPeer.start(fn _, _, pdu ->
        case pdu do
          <<f, _::16, quantity::16>> when f in [1, 2] ->
            <<f, div(quantity + 7, 8), 1>>

          <<f, _::16, quantity::16>> when f in [3, 4] ->
            registers = for _ <- 1..quantity, into: <<>>, do: <<0, 0>>
            <<f, quantity * 2, registers::binary>>

          <<f, address::16, quantity::16, _::binary>> when f in [15, 16] ->
            <<f, address::16, quantity::16>>

          echo ->
            echo
        end
      end)

    assert {:ok, session} =
             Modbus.connect(host: "127.0.0.1", port: port, timeout: 1000, transaction_id: 65_535)

    for function <- [:read_holding_registers, :read_input_registers],
        do: assert(apply(Modbus, function, [session, 0, 1]) == {:ok, [0]})

    for function <- [:read_coils, :read_discrete_inputs],
        do: assert(apply(Modbus, function, [session, 0, 1]) == {:ok, [true]})

    assert :ok = Modbus.write_holding_register(session, 0, 42)
    assert :ok = Modbus.write_holding_registers(session, 0, [42, 7])
    assert :ok = Modbus.write_coil(session, 0, true)
    assert :ok = Modbus.write_coils(session, 0, [true, false])
    assert :ok = Modbus.write_float(session, 0, 23.5)
    assert {:ok, +0.0} = Modbus.read_float(session, 0)
    assert {:ok, :healthy} = Modbus.health_check(session)

    for operation <- [
          :read_coils,
          :read_discrete_inputs,
          :read_holding_registers,
          :read_input_registers
        ] do
      expected = if operation in [:read_coils, :read_discrete_inputs], do: [true], else: [0]
      assert {:ok, ^expected} = Modbus.send(session, %{type: operation, address: 0, count: 1})
    end

    for message <- [
          %{type: :write_coil, address: 0, value: false},
          %{type: :write_holding_register, address: 0, value: 0},
          %{type: :write_coils, address: 0, values: [false, true]},
          %{type: :write_holding_registers, address: 0, values: [0, 1]}
        ],
        do: assert(Modbus.send(session, message) == :ok)

    assert {:error, %Error{}} = Modbus.send(session, %{})
    assert {:error, %Error{}} = Modbus.send(session, %{type: :wrong, address: 0})
    assert {:error, %Error{}} = Modbus.receive(session, 100)
    assert :not_supported = Modbus.subscribe(session, "temperature")
    assert :not_supported = Modbus.unsubscribe(session, make_ref())
    assert Modbus.capabilities().max_payload_size == 253
    assert :ok = Modbus.disconnect(session)
    assert :ok = Modbus.disconnect(session)
    assert :ok = Task.await(peer)
    assert {:error, %{code: :connection_closed}} = Modbus.read_holding_registers(session, 0, 1)
  end

  test "fragmented replies work and wrong transaction terminates session" do
    for tid <- [0, 99] do
      {peer, port} =
        TestPeer.start(fn _, _, _ -> {:split, <<tid::16, 0::16, 5::16, 1, 3, 2, 0, 42>>} end)

      {:ok, conn} = Modbus.connect(host: {127, 0, 0, 1}, port: port)
      monitor = Process.monitor(conn.pid)
      result = Modbus.read_holding_registers(conn, 0, 1)

      if tid == 0 do
        assert result == {:ok, [42]}
        Modbus.disconnect(conn)
      else
        assert {:error, %{code: :response_mismatch}} = result
      end

      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert :ok = Task.await(peer)
    end
  end

  test "WMB-D02 typed commands retain their unit while helpers use the session unit" do
    caller = self()

    {peer, port} =
      TestPeer.start(fn tid, unit, pdu ->
        send(caller, {:request, tid, unit, pdu})
        <<3, 2, unit::16>>
      end)

    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port, unit_id: 1)
    {:ok, command} = Command.new(:read_holding_registers, 4, 1, 2)
    assert {:ok, [2]} = Modbus.request(session, command)
    assert_receive {:request, 0, 2, <<3, 0, 4, 0, 1>>}
    assert {:ok, [1]} = Modbus.read_holding_registers(session, 5, 1)
    assert_receive {:request, 1, 1, <<3, 0, 5, 0, 1>>}
    assert :ok = Modbus.disconnect(session)
    assert :ok = Task.await(peer)
  end

  test "write timeout has unknown effect and a late reply cannot be reused" do
    {peer, port} =
      TestPeer.start(fn _, _, _ ->
        Process.sleep(80)
        <<6, 0, 0, 0, 1>>
      end)

    {:ok, conn} = Modbus.connect(host: "127.0.0.1", port: port, timeout: 20)

    assert {:error, %{effect: :unknown, details: %{reason: :timeout}}} =
             Modbus.write_holding_register(conn, 0, 1)

    assert {:error, _} = Modbus.write_holding_register(conn, 0, 2)
    assert :ok = Task.await(peer)
  end

  test "expired queued requests issue no writes" do
    test = self()

    {peer, port} =
      TestPeer.start(fn _, _, pdu ->
        send(test, {:wire, pdu})
        Process.sleep(100)
        <<3, 2, 0, 1>>
      end)

    {:ok, conn} = Modbus.connect(host: "127.0.0.1", port: port, timeout: 500)
    first = Task.async(fn -> Modbus.read_holding_registers(conn, 0, 1) end)
    assert_receive {:wire, <<3, 0, 0, 0, 1>>}
    {:ok, write} = Command.new(:write_holding_register, 0, 99)

    assert {:error, %{code: :deadline_exceeded, effect: :none}} =
             Connection.request(conn.pid, write, 20)

    assert {:ok, [1]} = Task.await(first)
    refute_receive {:wire, _}, 30
    Modbus.disconnect(conn)
    assert :ok = Task.await(peer)
  end

  test "owner normal termination closes the socket" do
    parent = self()
    {peer, port} = TestPeer.start(fn _, _, _ -> <<3, 2, 0, 1>> end)

    owner =
      Task.async(fn ->
        {:ok, conn} = Modbus.connect(host: "127.0.0.1", port: port)
        send(parent, {:connection, conn})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:connection, conn}
    monitor = Process.monitor(conn.pid)
    send(owner.pid, :finish)
    assert :ok = Task.await(owner)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert :ok = Task.await(peer)
  end

  test "remote exceptions do not destroy a usable session" do
    {peer, port} = TestPeer.start(fn _, _, <<f, _::binary>> -> <<f + 128, 2>> end)
    {:ok, conn} = Modbus.connect(host: "127.0.0.1", port: port)

    for _ <- 1..2,
        do: assert(match?({:error, %{code: :remote_exception}}, Modbus.health_check(conn)))

    Modbus.disconnect(conn)
    assert :ok = Task.await(peer)
  end

  test "invalid or unsupported configuration fails without sockets" do
    for opts <- [
          nil,
          [:bad],
          [host: "localhost"],
          [host: nil],
          [host: {999, 1, 1, 1}],
          [host: {1, 2}],
          [host: "127.0.0.1", security: :tls],
          [host: "127.0.0.1", securty: :tls],
          [host: "127.0.0.1", security: :none, security: :tls],
          [host: "127.0.0.1", unknown: true],
          [host: "127.0.0.1", port: 0],
          [host: "127.0.0.1", timeout: 0],
          [host: "127.0.0.1", unit_id: 0]
        ] do
      assert {:error, _} = Modbus.connect(opts)
    end

    assert {:error, _} = Connection.request(nil, nil, 0)
    {:ok, listener} = :gen_tcp.listen(0, active: false, ip: {127, 0, 0, 1})
    {:ok, {_, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)

    assert {:error, %{code: :connect_failed}} =
             Modbus.connect(host: "127.0.0.1", port: port, timeout: 20)
  end
end
