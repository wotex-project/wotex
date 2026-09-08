defmodule Wotex.Modbus.StreamFaultTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.Modbus
  alias Wotex.Modbus.{Codec, Command, ContractFixture, Error, TestPeer}

  test "WMB-S02 WMB-V03 every fixture ADU split retains exactly one unconsumed tail" do
    cases = Enum.filter(ContractFixture.pure_cases(), &(&1["operation"] == "codec.exchange"))

    for fixture <- cases do
      request = Base.decode16!(fixture["expectation"]["value"]["request_hex"], case: :lower)
      response = Base.decode16!(fixture["input"]["response_hex"], case: :lower)

      for bytes <- [request, response] do
        for split <- 0..(byte_size(bytes) - 1) do
          <<prefix::binary-size(^split), suffix::binary>> = bytes
          assert :more = Codec.decode(prefix), "#{fixture["id"]} split #{split}"
          assert {:ok, expected, <<>>} = Codec.decode(prefix <> suffix)
          assert {:ok, ^expected, ^request} = Codec.decode(prefix <> suffix <> request)
          assert {:ok, _, <<>>} = Codec.decode(request)
        end
      end
    end
  end

  test "WMB-S02 WMB-V03 MBAP length is rejected before a missing body can block" do
    for {protocol, length} <- [{1, 6}, {0, 0}, {0, 1}, {0, 255}, {0, 65_535}] do
      caller = self()

      {peer, port} =
        TestPeer.start(fn tid, _, _ ->
          send(caller, :request_seen)
          {:raw, <<tid::16, protocol::16, length::16>>}
        end)

      {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port, timeout: 1000)
      monitor = Process.monitor(session.pid)

      assert {:error, %Error{code: :invalid_mbap, effect: :none}} =
               Modbus.read_holding_registers(session, 0, 1)

      assert_receive :request_seen
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert :ok = Task.await(peer)
    end
  end

  for {name, command, fault, code} <- [
        {"transaction", {:read_holding_registers, 0, 1}, :wrong_transaction, :response_mismatch},
        {"unit", {:read_holding_registers, 0, 1}, :wrong_unit, :response_mismatch},
        {"function", {:read_holding_registers, 0, 1}, <<4, 2, 0, 42>>, :invalid_response},
        {"byte count", {:read_holding_registers, 0, 1}, <<3, 4, 0, 42>>, :invalid_response},
        {"extra read byte", {:read_holding_registers, 0, 1}, <<3, 2, 0, 42, 0>>, :invalid_response},
        {"coil padding", {:read_coils, 0, 1}, <<1, 1, 2>>, :invalid_padding},
        {"single coil address", {:write_coil, 1, true}, <<5, 0, 2, 255, 0>>, :response_mismatch},
        {"single coil value", {:write_coil, 1, true}, <<5, 0, 1, 0, 0>>, :response_mismatch},
        {"single register address", {:write_holding_register, 1, 42}, <<6, 0, 2, 0, 42>>,
         :response_mismatch},
        {"single register value", {:write_holding_register, 1, 42}, <<6, 0, 1, 0, 43>>,
         :response_mismatch},
        {"multiple coil address", {:write_coils, 1, [true]}, <<15, 0, 2, 0, 1>>, :invalid_response},
        {"multiple coil quantity", {:write_coils, 1, [true]}, <<15, 0, 1, 0, 2>>,
         :invalid_response},
        {"multiple register address", {:write_holding_registers, 1, [42]}, <<16, 0, 2, 0, 1>>,
         :invalid_response},
        {"multiple register quantity", {:write_holding_registers, 1, [42]}, <<16, 0, 1, 0, 2>>,
         :invalid_response}
      ] do
    test "WMB-S02 WMB-V04 #{name} failure closes before a later command can use stream bytes" do
      {operation, offset, input} = unquote(Macro.escape(command))
      fault = unquote(Macro.escape(fault))
      expected_code = unquote(code)
      caller = self()

      {peer, port} =
        TestPeer.start(fn tid, unit, pdu ->
          send(caller, {:wire_request, pdu})
          invalid = fault_frame(fault, tid, unit)
          future = frame(rem(tid + 1, 65_536), unit, <<3, 2, 0, 99>>)
          {:raw, invalid <> future}
        end)

      {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
      monitor = Process.monitor(session.pid)
      {:ok, command} = Command.new(operation, offset, input)
      expected_effect = if Command.write?(command), do: :unknown, else: :none

      assert {:error, %Error{code: ^expected_code, effect: ^expected_effect}} =
               Modbus.request(session, command)

      assert_receive {:wire_request, _}
      assert_receive {:DOWN, ^monitor, :process, _, :normal}

      assert {:error, %Error{code: :connection_closed, effect: :none}} =
               Modbus.write_holding_register(session, 0, 2)

      assert :ok = Task.await(peer)
      refute_received {:wire_request, _}
    end
  end

  test "WMB-S02 WMB-V05 known and unknown exception codes retain numeric status" do
    caller = self()

    {peer, port} =
      TestPeer.start(fn tid, _, <<function, _::binary>> ->
        code = Enum.at([1, 4, 255], div(tid, 2))
        send(caller, {:exception_sent, function, code})
        <<function + 128, code>>
      end)

    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)

    for code <- [1, 4, 255] do
      assert {:error,
              %Error{
                code: :remote_exception,
                effect: :none,
                details: %{exception_code: ^code, function: 3}
              }} =
               Modbus.read_holding_registers(session, 0, 1)

      assert_receive {:exception_sent, 3, ^code}

      assert {:error,
              %Error{
                code: :remote_exception,
                effect: :unknown,
                retryable: false,
                details: %{exception_code: ^code, function: 6}
              }} =
               Modbus.write_holding_register(session, 0, 42)

      assert_receive {:exception_sent, 6, ^code}
      assert Process.alive?(session.pid)
    end

    assert :ok = Modbus.disconnect(session)
    assert :ok = Task.await(peer)
  end

  test "WMB-S02 WMB-V05 truncated and extended exception PDUs cannot expose remote status" do
    for pdu <- [<<131>>, <<131, 2, 0>>] do
      {peer, port} = TestPeer.start(fn _, _, _ -> pdu end)
      {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
      monitor = Process.monitor(session.pid)

      assert {:error, %Error{code: :invalid_response, details: details}} =
               Modbus.read_holding_registers(session, 0, 1)

      refute Map.has_key?(details, :exception_code)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert :ok = Task.await(peer)
    end
  end

  test "WMB-S02 WMB-V03 EOF at every incomplete frame prefix is never success" do
    response = frame(0, 1, <<3, 2, 0, 42>>)

    for size <- 0..(byte_size(response) - 1) do
      prefix = binary_part(response, 0, size)
      {peer, port} = TestPeer.start(fn _, _, _ -> {:raw_close, prefix} end)
      {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port, timeout: 500)
      monitor = Process.monitor(session.pid)

      assert {:error, %Error{code: :transport_error, effect: :none}} =
               Modbus.read_holding_registers(session, 0, 1)

      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert :ok = Task.await(peer)
    end
  end

  test "WMB-S01 WMB-S02 response validation rejects forged commands and frame identities" do
    {:ok, command} = Command.new(:read_coils, 0, 1)
    good = %{transaction_id: 1, unit_id: 1, pdu: <<1, 1, 1>>}

    for forged <- [
          nil,
          %{command | address: nil},
          %{command | address: %{command.address | quantity: 0}},
          %{command | function: 256},
          %{command | values: [1 | :bad]}
        ] do
      assert {:error, %Error{code: :invalid_command}} = Codec.response(good, forged, 1)
    end

    for bad <- [
          %{good | transaction_id: 1.0},
          %{good | unit_id: 1.0},
          %{good | pdu: <<>>},
          %{good | pdu: nil},
          %{good | pdu: :binary.copy(<<0>>, 254)},
          %{},
          nil
        ] do
      assert {:error, %Error{code: :response_mismatch}} = Codec.response(bad, command, 1)
    end

    for tid <- [-1, 65_536, 1.0, nil] do
      assert {:error, %Error{code: :response_mismatch}} =
               Codec.response(%{good | transaction_id: tid}, command, tid)
    end
  end

  property "WMB-S02 WMB-V03 bounded arbitrary frames preserve the exact unread suffix" do
    check all(
            pdu <- binary(min_length: 1, max_length: 253),
            tail <- binary(max_length: 260),
            tid <- integer(0..65_535),
            unit <- integer(0..255)
          ) do
      bytes = frame(tid, unit, pdu)

      assert {:ok, %{transaction_id: ^tid, unit_id: ^unit, pdu: ^pdu}, ^tail} =
               Codec.decode(bytes <> tail)
    end
  end

  defp fault_frame(:wrong_transaction, tid, unit),
    do: frame(rem(tid + 1, 65_536), unit, <<3, 2, 0, 42>>)

  defp fault_frame(:wrong_unit, tid, unit), do: frame(tid, unit + 1, <<3, 2, 0, 42>>)
  defp fault_frame(pdu, tid, unit) when is_binary(pdu), do: frame(tid, unit, pdu)

  defp frame(tid, unit, pdu), do: <<tid::16, 0::16, byte_size(pdu) + 1::16, unit, pdu::binary>>
end
