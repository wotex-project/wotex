defmodule Wotex.Zigbee.Serial.CircuitsUART do
  @moduledoc """
  Identity-checked serial adapter backed by `Circuits.UART`.

  Configure `Wotex.Zigbee.Config` with this module as `:serial`, the USB serial
  number as `:device_id`, and `vendor_id` and `product_id` in
  `:serial_options`. The adapter enumerates ports and requires exactly one
  match. On macOS, a single `/dev/cu.*` and `/dev/tty.*` pair for the same
  device selects the callout port; any other duplicate is ambiguous. It checks
  the identity again after opening, so a disappearing port cannot silently
  turn into a different coordinator during startup. Ports without a serial
  number are refused.

  Each open starts a private process and UART owner. `Circuits.UART` opens the
  selected port exclusively. Received bytes and disconnects are forwarded to
  the coordinator owner through the `Wotex.Zigbee.SerialPort` messages. The
  process monitors the owner and closes the UART if that owner exits. Nothing
  is started when the package is loaded. USB reconnect requires a new explicit
  `Wotex.Zigbee.Owner` startup and a fresh version negotiation.

  `Circuits.UART` supports macOS and Linux, including supported Nerves targets.
  A target still needs the serial device, driver and permissions configured by
  its consumer. This adapter does not qualify any coordinator firmware.
  """

  @behaviour Wotex.Zigbee.SerialPort
  use GenServer

  @allowed ~w(baud_rate data_bits stop_bits parity flow_control vendor_id product_id uart_module)a

  @doc "Opens the unique USB device whose VID, PID and serial number match."
  @impl Wotex.Zigbee.SerialPort
  def open(device_id, options, owner) when is_binary(device_id) and is_pid(owner) do
    if valid_options?(options) do
      uart_module = Keyword.get(options, :uart_module, Circuits.UART)

      with {:ok, path} <- unique_path(uart_module, device_id, options),
           {:ok, port} <- GenServer.start(__MODULE__, {device_id, path, options, owner}) do
        case open_result(port) do
          :ok ->
            {:ok, port}

          {:error, reason} ->
            close(port)
            {:error, reason}
        end
      end
    else
      {:error, :invalid_options}
    end
  end

  def open(_, _, _), do: {:error, :invalid_options}

  @doc "Writes one MT frame to the owned serial port."
  @impl Wotex.Zigbee.SerialPort
  def write(port, bytes) when is_pid(port) and is_binary(bytes) do
    GenServer.call(port, {:write, bytes}, 5_000)
  catch
    :exit, _ -> {:error, :closed}
  end

  def write(_, _), do: {:error, :invalid_data}

  @doc "Closes the serial port and releases its private UART process."
  @impl Wotex.Zigbee.SerialPort
  def close(port) when is_pid(port) do
    GenServer.stop(port, :normal, 5_000)
    :ok
  catch
    :exit, _ -> :ok
  end

  def close(_), do: :ok

  @impl GenServer
  def init({device_id, path, options, owner}) do
    Process.flag(:trap_exit, true)
    uart_module = Keyword.get(options, :uart_module, Circuits.UART)

    with {:ok, ^path} <- unique_path(uart_module, device_id, options),
         {:ok, uart} <- uart_module.start_link() do
      case open_uart(uart_module, uart, path, options) do
        :ok ->
          case unique_path(uart_module, device_id, options) do
            {:ok, ^path} ->
              {:ok,
               %{
                 open_result: :ok,
                 owner: owner,
                 owner_monitor: Process.monitor(owner),
                 uart: uart,
                 uart_module: uart_module,
                 path: path
               }}

            {:ok, _} ->
              stop_uart(uart_module, uart)
              {:ok, %{open_result: {:error, :identity_changed}}}

            {:error, reason} ->
              stop_uart(uart_module, uart)
              {:ok, %{open_result: {:error, reason}}}
          end

        {:error, reason} ->
          stop_uart(uart_module, uart)
          {:ok, %{open_result: {:error, reason}}}
      end
    else
      {:ok, _} -> {:ok, %{open_result: {:error, :identity_changed}}}
      {:error, reason} -> {:ok, %{open_result: {:error, reason}}}
    end
  end

  @impl GenServer
  def handle_call(:open_result, _, state), do: {:reply, state.open_result, state}

  def handle_call({:write, bytes}, _, state) do
    case state.uart_module.write(state.uart, bytes) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        send(state.owner, {:zigbee_serial_down, self(), reason})
        {:stop, :normal, {:error, :serial_write_failed}, state}
    end
  end

  @impl GenServer
  def handle_info({:circuits_uart, uart, bytes}, %{uart: uart} = state)
      when is_binary(bytes) do
    send(state.owner, {:zigbee_serial, self(), bytes})
    {:noreply, state}
  end

  def handle_info({:circuits_uart, uart, {:error, reason}}, %{uart: uart} = state) do
    send(state.owner, {:zigbee_serial_down, self(), reason})
    {:stop, :normal, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, owner, _},
        %{owner_monitor: monitor, owner: owner} = state
      ),
      do: {:stop, :normal, state}

  def handle_info({:EXIT, uart, reason}, %{uart: uart} = state) do
    send(state.owner, {:zigbee_serial_down, self(), reason})
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, %{uart: _} = state) do
    stop_uart(state.uart_module, state.uart)
    :ok
  end

  def terminate(_, _), do: :ok

  defp valid_options?(options) do
    Keyword.keyword?(options) and
      Enum.all?(Keyword.keys(options), &(&1 in @allowed)) and
      length(options) == length(Enum.uniq(Keyword.keys(options))) and
      byte_option?(Keyword.get(options, :vendor_id)) and
      byte_option?(Keyword.get(options, :product_id)) and
      Keyword.get(options, :baud_rate) == 115_200 and
      Keyword.get(options, :data_bits) == 8 and
      Keyword.get(options, :stop_bits) == 1 and
      Keyword.get(options, :parity) == :none and
      Keyword.get(options, :flow_control) in [:none, :rts_cts] and
      uart_module?(Keyword.get(options, :uart_module, Circuits.UART))
  end

  defp byte_option?(value), do: is_integer(value) and value >= 0 and value <= 65_535

  defp uart_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      Enum.all?(
        [{:enumerate, 0}, {:start_link, 0}, {:open, 3}, {:write, 2}, {:close, 1}, {:stop, 1}],
        fn {function, arity} -> function_exported?(module, function, arity) end
      )
  end

  defp uart_module?(_), do: false

  defp unique_path(uart_module, device_id, options) do
    matches =
      uart_module.enumerate()
      |> Enum.filter(fn {_, info} ->
        is_map(info) and Map.get(info, :serial_number) == device_id and
          Map.get(info, :vendor_id) == options[:vendor_id] and
          Map.get(info, :product_id) == options[:product_id]
      end)

    case matches do
      [{path, _}] when is_binary(path) -> {:ok, path}
      [] -> {:error, :identity_not_found}
      [first, second] -> callout_pair(first, second)
      _ -> {:error, :ambiguous_identity}
    end
  end

  defp callout_pair({first, _}, {second, _}) when is_binary(first) and is_binary(second) do
    cond do
      String.starts_with?(first, "/dev/cu.") and
          second == String.replace_prefix(first, "/dev/cu.", "/dev/tty.") ->
        {:ok, first}

      String.starts_with?(second, "/dev/cu.") and
          first == String.replace_prefix(second, "/dev/cu.", "/dev/tty.") ->
        {:ok, second}

      true ->
        {:error, :ambiguous_identity}
    end
  end

  defp callout_pair(_, _), do: {:error, :ambiguous_identity}

  defp open_result(port) do
    GenServer.call(port, :open_result)
  catch
    :exit, _ -> {:error, :serial_open_failed}
  end

  defp open_uart(uart_module, uart, path, options) do
    flow_control = if options[:flow_control] == :rts_cts, do: :hardware, else: :none

    uart_module.open(uart, path,
      speed: 115_200,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: flow_control,
      active: true,
      id: :pid
    )
  end

  defp stop_uart(uart_module, uart) do
    if Process.alive?(uart) do
      uart_module.close(uart)
      uart_module.stop(uart)
    end
  end
end
