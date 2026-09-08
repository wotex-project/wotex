defmodule Wotex.Modbus.BoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.Modbus
  alias Wotex.Modbus.{Address, Codec, Command, Connection, ContractFixture, Error, Session, Value}

  @fixture_digest ContractFixture.digest()
  @reads [
    read_coils: 2000,
    read_discrete_inputs: 2000,
    read_holding_registers: 125,
    read_input_registers: 125
  ]
  @writes [write_coils: {1968, true}, write_holding_registers: {123, 65_535}]

  for fixture <- ContractFixture.pure_cases() do
    @tag fixture_sha256: @fixture_digest
    @tag requirement: fixture["requirements"]
    @tag scenario: fixture["scenarios"]
    test "WMB-D04 exact fixture #{fixture["id"]}" do
      fixture = unquote(Macro.escape(fixture))
      assert fixture["expectation"]["operator"] == "exact"
      assert ContractFixture.run(fixture) == fixture["expectation"]["value"]
    end
  end

  test "WMB-S01 WMB-V01 every quantity and address edge is admitted exactly" do
    for {operation, maximum} <- @reads, quantity <- [1, maximum] do
      assert {:ok, command} = Command.new(operation, 65_536 - quantity, quantity, 255)
      assert {:ok, _} = Codec.encode(command, 65_535)
      assert command.address.quantity == quantity
      assert command.address.unit_id == 255

      code = if quantity == 1, do: :invalid_address, else: :address_overflow

      assert {:error, %Error{code: ^code}} =
               Command.new(operation, 65_537 - quantity, quantity)
    end

    for {operation, maximum} <- @reads, quantity <- [0, maximum + 1, nil, 1.0] do
      assert {:error, %Error{effect: :none}} = Command.new(operation, 0, quantity)
      assert {:error, %Error{effect: :none}} = apply(Modbus, operation, [session(), 0, quantity])
    end

    for {operation, {maximum, value}} <- @writes, quantity <- [1, maximum] do
      values = List.duplicate(value, quantity)
      assert {:ok, command} = Command.new(operation, 65_536 - quantity, values)
      assert {:ok, _} = Codec.encode(command, 1)

      code = if quantity == 1, do: :invalid_address, else: :address_overflow

      assert {:error, %Error{code: ^code}} =
               Command.new(operation, 65_537 - quantity, values)
    end

    for {operation, {maximum, value}} <- @writes, quantity <- [0, maximum + 1] do
      values = List.duplicate(value, quantity)
      assert {:error, %Error{code: :invalid_quantity}} = Command.new(operation, 0, values)
      assert {:error, %Error{effect: :none}} = apply(Modbus, operation, [session(), 0, values])
    end

    for unit <- [1, 247, 255], do: assert(match?({:ok, _}, Address.new(0, 1, unit)))

    for unit <- [0, 248, 254, 256, 255.0, nil],
        do: assert(match?({:error, %Error{code: :invalid_unit}}, Address.new(0, 1, unit)))

    refute_received {:"$gen_call", _, _}
  end

  test "WMB-S01 WMB-V02 forged commands and sessions never reach dispatch" do
    {:ok, command} = Command.new(:write_holding_registers, 0, [1])

    forged = [
      %{command | function: 256},
      %{command | function: 16.0},
      %{command | address: %{command.address | offset: -1}},
      %{command | address: %{command.address | unit_id: -1}},
      %{command | address: %{command.address | quantity: 2}},
      %{command | address: nil},
      %{command | values: [1 | :invalid]},
      %{command | values: List.duplicate(1, 124)},
      %{command | values: [65_536]}
    ]

    for input <- forged ++ [nil, %{}, command.address] do
      assert {:error, %Error{code: :invalid_command, effect: :none}} = Command.validate(input)
      assert {:error, %Error{effect: :none}} = Codec.encode(input, 1)
      assert {:error, %Error{effect: :none}} = Modbus.request(session(), input)
      assert {:error, %Error{effect: :none}} = Connection.request(self(), input, 1)
    end

    for bad <- [
          nil,
          %{},
          %{session() | pid: nil},
          %{session() | unit_id: 255.0},
          %{session() | timeout: 0},
          %{session() | timeout: 60_001}
        ] do
      assert {:error, %Error{code: :invalid_session}} = Modbus.request(bad, command)
      assert {:error, %Error{code: :invalid_session}} = Modbus.read_holding_registers(bad, 0, 1)
      assert {:error, %Error{code: :invalid_session}} = Modbus.write_coil(bad, 0, true)
      assert {:error, %Error{code: :invalid_session}} = Modbus.disconnect(bad)
    end

    refute Command.write?(nil)
    refute_received {:"$gen_call", _, _}
  end

  test "WMB-D02 compatibility maps require exactly one operation-appropriate input" do
    for message <- [
          %{type: :read_coils, address: 0},
          %{type: :read_coils, address: 0, value: 1},
          %{type: :read_coils, address: 0, count: 1, value: 1},
          %{type: :write_coil, address: 0, count: 1},
          %{type: :write_coils, address: 0, value: true},
          %{type: :write_holding_register, address: 0, value: 1, values: [1]},
          %{type: :read_coils, address: 0, count: 1, unknown: nil},
          %{type: "read_coils", address: 0, count: 1},
          %{nil => true, type: :unknown, address: 0}
        ] do
      assert {:error, %Error{code: :invalid_message, effect: :none}} =
               Modbus.send(session(), message)
    end

    refute_received {:"$gen_call", _, _}
  end

  test "WMB-S01 WMB-V06 proper bounded lists and unique conversion options" do
    for input <- [[1 | nil], [1 | :tail], [1, 2 | %{}], nil, "1"] do
      assert {:error, %Error{}} = Command.new(:write_holding_registers, 0, input)
      assert {:error, %Error{}} = Command.new(:write_coils, 0, input)
      assert {:error, %Error{code: :invalid_value}} = Value.decode(input, :uint32)
    end

    for options <- [
          [byte_order: :big, byte_order: :big],
          [word_order: :little, word_order: :big],
          [unknown: :big],
          [{:byte_order, :big} | :tail],
          [{"byte_order", :big}],
          nil
        ] do
      assert {:error, %Error{code: :invalid_order}} = Value.encode(1, :uint16, options)
      assert {:error, %Error{code: :invalid_order}} = Value.decode([1], :uint16, options)
    end

    for options <- [
          [host: "127.0.0.1", unit_id: 255.0],
          [{:host, "127.0.0.1"} | :tail],
          [host: "127.0.0.1", host: "127.0.0.2"]
        ],
        do: assert(match?({:error, %Error{code: :invalid_options}}, Modbus.connect(options)))
  end

  test "WMB-S01 WMB-V06 integer boundaries and four orders have exact independent words" do
    for {kind, bits, signed?} <- [
          {:uint16, 16, false},
          {:int16, 16, true},
          {:uint32, 32, false},
          {:int32, 32, true},
          {:uint64, 64, false},
          {:int64, 64, true}
        ] do
      minimum = if signed?, do: -Integer.pow(2, bits - 1), else: 0
      maximum = Integer.pow(2, bits - if(signed?, do: 1, else: 0)) - 1

      for value <- [minimum, maximum, 0], byte <- [:big, :little], word <- [:big, :little] do
        bytes = <<value::size(bits)>>
        expected = expected_words(bytes, byte, word)
        options = [byte_order: byte, word_order: word]
        assert {:ok, ^expected} = Value.encode(value, kind, options)
        assert {:ok, ^value} = Value.decode(expected, kind, options)
      end

      for value <- [minimum - 1, maximum + 1, nil, true, 1.0],
          do: assert(match?({:error, %Error{code: :invalid_value}}, Value.encode(value, kind)))
    end
  end

  test "WMB-S01 WMB-V06 float bit patterns preserve finite extremes and signed zero" do
    for {kind, bits, encodings} <- [
          {:float32, 32, [0, 0x80000000, 1, 0x80000001, 0x7F7FFFFF, 0xFF7FFFFF]},
          {:float64, 64,
           [0, 0x8000000000000000, 1, 0x8000000000000001, 0x7FEFFFFFFFFFFFFF, 0xFFEFFFFFFFFFFFFF]}
        ],
        encoding <- encodings,
        byte <- [:big, :little],
        word <- [:big, :little] do
      bytes = <<encoding::size(bits)>>
      <<value::float-size(^bits)>> = bytes
      expected = expected_words(bytes, byte, word)
      options = [byte_order: byte, word_order: word]
      assert {:ok, ^expected} = Value.encode(value, kind, options)
      assert {:ok, decoded} = Value.decode(expected, kind, options)
      assert <<decoded::float-size(bits)>> == bytes
    end

    for {kind, bits, values} <- [
          {:float32, 32, [0x7F800000, 0xFF800000, 0x7FC00000, 0x7F800001]},
          {:float64, 64,
           [0x7FF0000000000000, 0xFFF0000000000000, 0x7FF8000000000000, 0x7FF0000000000001]}
        ],
        value <- values,
        byte <- [:big, :little],
        word <- [:big, :little] do
      words = expected_words(<<value::size(bits)>>, byte, word)

      assert {:error, %Error{code: :invalid_value}} =
               Value.decode(words, kind, byte_order: byte, word_order: word)
    end
  end

  property "WMB-S01 WMB-V02 malformed register tails always fail without dispatch" do
    check all(
            values <- list_of(integer(), max_length: 8),
            tail <- one_of([integer(), binary(), constant(nil)])
          ) do
      input = Enum.reduce(Enum.reverse(values), tail, &[&1 | &2])
      assert {:error, %Error{}} = Command.new(:write_holding_registers, 0, input)
      assert {:error, %Error{}} = Value.decode(input, :uint64)
      refute_received {:"$gen_call", _, _}
    end
  end

  test "WMB-C02 WMB-D02 malformed numeric host bytes fail before socket acquisition" do
    for host <- [<<255>>, <<195>>, "127.0.0.1" <> <<255>>, <<0>>, :binary.copy("1", 65)] do
      assert {:error, %Error{code: :invalid_host, field: :host, effect: :none}} =
               Connection.config(host: host)

      assert {:error, %Error{code: :invalid_host, field: :host, effect: :none}} =
               Modbus.connect(host: host)
    end
  end

  defp session, do: %Session{pid: self(), unit_id: 1, timeout: 1}

  defp expected_words(bytes, byte_order, word_order) do
    words = for <<word::binary-size(2) <- bytes>>, do: :binary.decode_unsigned(word, byte_order)
    if word_order == :little, do: Enum.reverse(words), else: words
  end
end
