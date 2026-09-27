defmodule Wotex.Zigbee.CircuitsUARTTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Zigbee.{Config, Owner}
  alias Wotex.Zigbee.Serial.CircuitsUART
  alias Wotex.Zigbee.TestUART

  @device %{
    vendor_id: 0x0451,
    product_id: 0x16A8,
    serial_number: "coordinator-001"
  }
  @options [
    baud_rate: 115_200,
    data_bits: 8,
    stop_bits: 1,
    parity: :none,
    flow_control: :rts_cts,
    vendor_id: 0x0451,
    product_id: 0x16A8,
    uart_module: TestUART
  ]

  setup do
    fixture = TestUART.start_fixture(self(), %{"/dev/cu.test" => @device})
    on_exit(fn -> TestUART.stop_fixture(fixture) end)
    :ok
  end

  test "opens exact hardware identity and forwards raw bytes and disconnect" do
    assert {:ok, port} = CircuitsUART.open("coordinator-001", @options, self())

    assert_receive {:uart_open, uart, "/dev/cu.test", uart_options}
    assert uart_options[:speed] == 115_200
    assert uart_options[:flow_control] == :hardware
    assert uart_options[:active]
    assert uart_options[:id] == :pid

    send(port, {:circuits_uart, uart, <<0xFE, 0, 1>>})
    assert_receive {:zigbee_serial, ^port, <<0xFE, 0, 1>>}

    assert :ok = CircuitsUART.write(port, <<1, 2, 3>>)
    assert_receive {:uart_write, ^uart, <<1, 2, 3>>}

    monitor = Process.monitor(port)
    send(port, {:circuits_uart, uart, {:error, :eio}})
    assert_receive {:zigbee_serial_down, ^port, :eio}
    assert_receive {:uart_close, ^uart}
    assert_receive {:DOWN, ^monitor, :process, ^port, :normal}
  end

  test "refuses missing, ambiguous and incomplete identities without opening" do
    assert {:error, :identity_not_found} = CircuitsUART.open("other", @options, self())
    assert {:error, :invalid_options} = CircuitsUART.open("coordinator-001", [], self())

    assert {:error, :invalid_options} =
             CircuitsUART.open(
               "coordinator-001",
               Keyword.put(@options, :uart_module, :missing),
               self()
             )

    assert {:error, :invalid_options} = CircuitsUART.open(1, @options, self())
    assert {:error, :invalid_data} = CircuitsUART.write(self(), :not_bytes)

    Agent.update(:persistent_term.get({TestUART, :fixture}), fn state ->
      %{state | ports: %{"a" => @device, "b" => @device}}
    end)

    assert {:error, :ambiguous_identity} = CircuitsUART.open("coordinator-001", @options, self())
    refute_receive {:uart_open, _, _, _}
  end

  test "refuses multiple USB interfaces with the same identity" do
    fixture = :persistent_term.get({TestUART, :fixture})

    Agent.update(fixture, fn state ->
      %{
        state
        | ports: %{
            "/dev/cu.test" => @device,
            "/dev/tty.test" => @device,
            "/dev/cu.other" => @device
          }
      }
    end)

    assert {:error, :ambiguous_identity} = CircuitsUART.open("coordinator-001", @options, self())
    refute_receive {:uart_open, _, _, _}
  end

  test "a macOS dial-in and callout pair selects only the callout port" do
    fixture = :persistent_term.get({TestUART, :fixture})

    Agent.update(fixture, fn state ->
      %{
        state
        | ports: %{"/dev/cu.test" => @device, "/dev/tty.test" => @device},
          ports_after_open: %{"/dev/cu.test" => @device, "/dev/tty.test" => @device}
      }
    end)

    assert {:ok, port} = CircuitsUART.open("coordinator-001", @options, self())
    assert_receive {:uart_open, uart, "/dev/cu.test", _}
    assert :ok = CircuitsUART.close(port)
    assert_receive {:uart_close, ^uart}
  end

  test "refuses an identity that changes after opening and releases the port" do
    fixture = :persistent_term.get({TestUART, :fixture})
    Agent.update(fixture, &Map.put(&1, :ports_after_open, %{}))

    assert {:error, :identity_not_found} =
             CircuitsUART.open("coordinator-001", @options, self())

    assert_receive {:uart_open, uart, "/dev/cu.test", _}
    assert_receive {:uart_close, ^uart}
  end

  test "refuses a re-enumerated port path even when USB identifiers match" do
    fixture = :persistent_term.get({TestUART, :fixture})
    Agent.update(fixture, &Map.put(&1, :ports_after_open, %{"/dev/cu.other" => @device}))

    assert {:error, :identity_changed} =
             CircuitsUART.open("coordinator-001", @options, self())

    assert_receive {:uart_open, uart, "/dev/cu.test", _}
    assert_receive {:uart_close, ^uart}
  end

  test "returns open and write failures and closes when its owner exits" do
    fixture = :persistent_term.get({TestUART, :fixture})
    Agent.update(fixture, &Map.put(&1, :open_result, {:error, :eacces}))
    assert {:error, :eacces} = CircuitsUART.open("coordinator-001", @options, self())
    assert_receive {:uart_open, uart, _, _}
    assert_receive {:uart_close, ^uart}

    Agent.update(fixture, fn state -> %{state | open_result: :ok, write_result: {:error, :eio}} end)

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert {:ok, port} = CircuitsUART.open("coordinator-001", @options, owner)
    monitor = Process.monitor(port)
    assert {:error, :serial_write_failed} = CircuitsUART.write(port, <<1>>)
    assert_receive {:uart_close, _}
    assert_receive {:DOWN, ^monitor, :process, ^port, :normal}
    send(owner, :stop)
  end

  test "returns UART worker startup failure without retaining a port" do
    fixture = :persistent_term.get({TestUART, :fixture})
    Agent.update(fixture, &Map.put(&1, :start_result, {:error, :unavailable}))

    assert {:error, :unavailable} = CircuitsUART.open("coordinator-001", @options, self())
    refute_receive {:uart_open, _, _, _}
  end

  test "owner death closes its UART" do
    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert {:ok, port} = CircuitsUART.open("coordinator-001", @options, owner)
    assert_receive {:uart_open, uart, _, _}
    monitor = Process.monitor(port)
    send(owner, :stop)
    assert_receive {:uart_close, ^uart}
    assert_receive {:DOWN, ^monitor, :process, ^port, :normal}
  end

  test "UART process loss invalidates the adapter and notifies its owner" do
    assert {:ok, port} = CircuitsUART.open("coordinator-001", @options, self())
    assert_receive {:uart_open, uart, _, _}
    monitor = Process.monitor(port)

    Process.exit(uart, :kill)
    assert_receive {:zigbee_serial_down, ^port, :killed}
    assert_receive {:DOWN, ^monitor, :process, ^port, :normal}
    assert {:error, :closed} = CircuitsUART.write(port, <<1>>)
    assert :ok = CircuitsUART.close(port)
  end

  test "software flow control stays disabled and an explicit close releases the port" do
    options = Keyword.put(@options, :flow_control, :none)
    assert {:ok, port} = CircuitsUART.open("coordinator-001", options, self())
    assert_receive {:uart_open, uart, _, uart_options}
    assert uart_options[:flow_control] == :none
    assert :ok = CircuitsUART.close(port)
    assert_receive {:uart_close, ^uart}
    assert :ok = CircuitsUART.close(port)
  end

  test "the coordinator owner negotiates SYS_VERSION through the serial adapter" do
    {:ok, config} =
      Config.new(
        serial: CircuitsUART,
        device_id: "coordinator-001",
        expected_version: {2, 0, 3, 2, 0},
        serial_options: [vendor_id: 0x0451, product_id: 0x16A8, uart_module: TestUART]
      )

    assert {:ok, owner} = Owner.start(config)
    assert_receive {:uart_open, uart, "/dev/cu.test", _}
    assert_receive {:uart_write, ^uart, <<0xFE, 0, 0x21, 2, 0x23>>}

    adapter = Agent.get(uart, & &1.parent)
    send(adapter, {:circuits_uart, uart, <<0xFE, 5, 0x61, 2, 2, 0, 3, 2, 0, 0x65>>})

    assert {:ok, handle} = Owner.ready(owner, 1_000)
    assert :ok = Wotex.Zigbee.close(handle)
    assert_receive {:uart_close, ^uart}
  end
end
