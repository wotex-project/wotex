defmodule Wotex.Modbus.CompatibilityTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.{Form, Modbus}
  alias Wotex.Modbus.{Command, Error, Mapping, TestPeer, Value}

  test "WMB-S04 WMB-V09 explicit health probes retain all four read functions, units and ranges" do
    test = self()

    {peer, port} =
      TestPeer.start(fn _, unit, <<function, offset::16, quantity::16>> ->
        send(test, {:probe, function, unit, offset, quantity})

        cond do
          offset == 0 -> <<function + 128, 2>>
          function in [1, 2] -> <<function, 1, 3>>
          true -> <<function, 4, 0, 42, 0, 43>>
        end
      end)

    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)

    assert {:error, %Error{code: :remote_exception, details: %{exception_code: 2}}} =
             Modbus.health_check(session)

    assert_receive {:probe, 3, 1, 0, 1}

    for {operation, function} <- [
          read_coils: 1,
          read_discrete_inputs: 2,
          read_holding_registers: 3,
          read_input_registers: 4
        ] do
      {:ok, probe} = Command.new(operation, 10, 2, 2)
      assert {:ok, :healthy} = Modbus.health_check(session, probe)
      assert_receive {:probe, ^function, 2, 10, 2}
    end

    for {operation, value} <- [
          write_coil: true,
          write_coils: [true],
          write_holding_register: 42,
          write_holding_registers: [42]
        ] do
      {:ok, write} = Command.new(operation, 10, value)

      assert {:error, %Error{code: :invalid_health_probe, effect: :none}} =
               Modbus.health_check(session, write)
    end

    assert {:error, %Error{code: :invalid_command}} = Modbus.health_check(session, nil)
    {:ok, probe} = Command.new(:read_coils, 10, 1)

    assert {:error, %Error{code: :invalid_command}} =
             Modbus.health_check(session, %{probe | address: %{probe.address | quantity: 2001}})

    assert {:error, %Error{code: :invalid_session}} = Modbus.health_check(nil, probe)
    :ok = Modbus.disconnect(session)
    assert :ok = Task.await(peer)
    refute_received {:probe, _, _, _, _}
  end

  test "WMB-D01 WMB-D02 WMB-D03 standalone float write, raw readback and explicit probe workflow" do
    test = self()

    {peer, port} =
      TestPeer.start(fn _, _, pdu ->
        send(test, {:wire, pdu})

        case pdu do
          <<16, offset::16, quantity::16, byte_count, values::binary>> ->
            assert byte_count == 2 * quantity
            assert byte_size(values) == byte_count
            Process.put({:registers, offset}, values)
            <<16, offset::16, quantity::16>>

          <<3, offset::16, quantity::16>> ->
            values = binary_part(Process.get({:registers, offset}), 0, quantity * 2)
            <<3, quantity * 2, values::binary>>
        end
      end)

    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
    socket = :sys.get_state(session.pid).socket
    monitor = Process.monitor(session.pid)

    try do
      {:ok, words} = Value.encode(25.5, :float32)
      assert words == [16_844, 0]
      assert :ok = Modbus.write_holding_registers(session, 10, words)
      assert {:ok, [16_844, 0]} = Modbus.read_holding_registers(session, 10, 2)
      assert {:ok, 25.5} = Modbus.read_float(session, 10)
      {:ok, probe} = Command.new(:read_holding_registers, 10, 1)
      assert {:ok, :healthy} = Modbus.health_check(session, probe)
      assert :ok = Modbus.write_float(session, 10, -1.5)
      assert {:ok, -1.5} = Modbus.read_float(session, 10)
    after
      :ok = Modbus.disconnect(session)
    end

    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert :erlang.port_info(socket) == :undefined
    assert :ok = Task.await(peer)
    assert_receive {:wire, <<16, 0, 10, 0, 2, 4, 0x41, 0xCC, 0, 0>>}
    assert_receive {:wire, <<3, 0, 10, 0, 2>>}
    assert_receive {:wire, <<3, 0, 10, 0, 2>>}
    assert_receive {:wire, <<3, 0, 10, 0, 1>>}
    assert_receive {:wire, <<16, 0, 10, 0, 2, 4, 0xBF, 0xC0, 0, 0>>}
    assert_receive {:wire, <<3, 0, 10, 0, 2>>}
    refute_received {:wire, _}
  end

  test "WMB-S04 WMB-V10 capabilities distinguish PDU and TCP ADU limits" do
    assert %{
             functions: [1, 2, 3, 4, 5, 6, 15, 16],
             transport: [:tcp],
             security: [:none],
             max_payload_size: 253,
             max_adu_size: 260,
             supports_streaming: false,
             discovery_capable: false,
             qos_levels: [:at_most_once]
           } = Modbus.capabilities()

    assert {:error, %Error{code: :not_supported}} = Modbus.receive(nil, 1)
    assert :not_supported = Modbus.subscribe(nil, nil)
    assert :not_supported = Modbus.unsubscribe(nil, nil)
  end

  test "WMB-S04 WMB-V10 scalar Form widths fail during pure mapping, before any request" do
    for {type, width} <- [
          {"xsd:short", 1},
          {"xsd:unsignedShort", 1},
          {"xsd:int", 2},
          {"xsd:unsignedInt", 2},
          {"xsd:long", 4},
          {"xsd:unsignedLong", 4},
          {"xsd:float", 2},
          {"xsd:double", 4}
        ],
        entity <- ["HoldingRegister", "InputRegister"] do
      input = %{"modv:entity" => entity, "modv:type" => type}
      assert {:ok, _} = Mapping.command(form(input, width), :readproperty)

      for wrong <- Enum.reject([1, 2, 3, 4, 5], &(&1 == width)) do
        assert {:error, %Error{code: :quantity_mismatch}} =
                 Mapping.command(form(input, wrong), :readproperty)
      end
    end

    for entity <- ["Coil", "DiscreteInput"] do
      assert {:error, %Error{code: :unsupported_conversion}} =
               Mapping.command(
                 form(%{"modv:entity" => entity, "modv:type" => "xsd:short"}),
                 :readproperty
               )
    end
  end

  test "WMB-S04 WMB-V10 numeric endpoints and exact path/query shape survive explicit base resolution" do
    for path <- [
          "/1//1",
          "//1/1",
          "/1/1/",
          "/1/1/extra",
          "/1/1?other=1",
          "/1/1?quantity=1&quantity=1",
          "/1/1?quantity=",
          "/1/1?quantity=2&other=1"
        ] do
      input = form(%{"href" => "modbus+tcp://127.0.0.1" <> path})
      assert {:error, %Error{}} = Mapping.command(input, :readproperty)
    end

    assert {:error, %Error{code: :invalid_host}} =
             Mapping.command(form(%{"href" => "modbus+tcp://localhost/1/1"}), :readproperty)

    assert {:ok, mapping} =
             Mapping.command(form(%{"href" => "modbus+tcp://[::1]:1502/255/65536"}), :readproperty)

    assert mapping.endpoint == %{host: "::1", port: 1502}
    assert mapping.command.address.offset == 65_535
    assert mapping.command.address.unit_id == 255

    for base <- ["relative/base", "http://127.0.0.1/", "modbus+tcp://user@127.0.0.1/", "::"] do
      assert {:error, %Error{code: :invalid_href}} =
               Mapping.command(form(%{"href" => "/1/1"}), :readproperty, nil, base: base)
    end

    for opts <- [nil, %{}, [base: 42], [base: "a", base: "b"], [unknown: true], [:bad | :tail]] do
      assert {:error, %Error{code: :invalid_options}} =
               Mapping.command(form(%{}), :readproperty, nil, opts)
    end
  end

  test "WMB-S04 WMB-V10 descriptive extensions remain intact and cannot authorize writes" do
    source =
      form(%{
        "modv:entity" => "InputRegister",
        "modv:function" => "writeSingleHoldingRegister",
        "modv:timeout" => 999_999,
        "modv:pollingTime" => 0,
        "vendor:settings" => %{"byte-order" => "unknown", "security" => "custom"}
      })

    {:ok, typed} = Form.new(source)
    assert {:ok, mapping} = Mapping.command(typed, :readproperty)
    assert mapping.command.function == 4
    assert Form.to_map(mapping.form) == source

    assert {:error, %Error{code: :unsupported_operation}} =
             Mapping.command(typed, :writeproperty, 42)

    assert {:error, _} = Mapping.command(%Form{value: %{}}, :readproperty)
    assert {:error, _} = Mapping.command(%Form{value: nil}, :readproperty)
    assert {:error, %Error{code: :invalid_mapping}} = Mapping.decode(%{}, [42])
  end

  defp form(extra, quantity \\ 1) do
    Map.merge(
      %{
        "href" => "modbus+tcp://127.0.0.1/1/1?quantity=#{quantity}",
        "modv:entity" => "HoldingRegister"
      },
      extra
    )
  end
end
