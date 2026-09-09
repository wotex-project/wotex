defmodule Wotex.CoAP.TestDatagram do
  @moduledoc false

  @behaviour Wotex.CoAP.Datagram
  use GenServer
  import Kernel, except: [send: 2]
  alias Wotex.CoAP.{Datagram, Error}

  @impl Datagram
  @spec open(Datagram.config(), pid(), pos_integer()) ::
          {:ok, Datagram.handle()} | {:error, Error.t()}
  def open(%{options: %{test: test, mode: mode}} = config, owner, _) do
    Kernel.send(test, {:opening, self(), owner, config.generation})

    case mode do
      :open_error ->
        {:error, Error.new(:socket_failed)}

      :open_raise ->
        raise "injected adapter fault"

      :open_malformed ->
        :invalid

      :open_block ->
        receive do
          :release -> started(config, owner)
        end

      _ ->
        started(config, owner)
    end
  end

  defp started(config, owner) do
    {:ok, pid} = GenServer.start(__MODULE__, {config, owner})
    Kernel.send(config.options.test, {:adapter, pid, config.generation})
    {:ok, %{pid: pid, generation: config.generation}}
  end

  @impl Datagram
  @spec send(Datagram.handle(), binary()) :: :ok | {:error, Error.t()}
  def send(handle, bytes), do: callback(GenServer.call(handle.pid, {:send, bytes}))

  @impl Datagram
  @spec set_active_once(Datagram.handle()) :: :ok | {:error, Error.t()}
  def set_active_once(handle), do: callback(GenServer.call(handle.pid, :arm))

  @impl Datagram
  @spec close(Datagram.handle()) :: :ok | {:error, Error.t()}
  def close(handle), do: callback(GenServer.call(handle.pid, :close))

  defp callback(:raise), do: raise("injected callback fault")
  defp callback(other), do: other

  defp outcome(mode, failure, kind) do
    cond do
      {kind, mode} in [{:send, :send_raise}, {:arm, :arm_raise}, {:close, :close_raise}] -> :raise
      {kind, mode} in [{:send, :send_malformed}, {:arm, :arm_malformed}] -> :malformed
      failure -> {:error, Error.new(:transport_error)}
      true -> :ok
    end
  end

  @impl GenServer
  def init({config, owner}) do
    {:ok, %{config: config, owner: owner, monitor: Process.monitor(owner), sends: 0, arms: 0}}
  end

  @impl GenServer
  def handle_call({:send, bytes}, _, state) do
    Kernel.send(state.config.options.test, {:sent_datagram, self(), bytes})
    count = state.sends + 1
    mode = state.config.options.mode
    fail = mode == :send_error or (mode == :ack_error and count == 2)

    {:reply, outcome(mode, fail, :send), %{state | sends: count}}
  end

  def handle_call(:arm, _, state) do
    count = state.arms + 1
    mode = state.config.options.mode
    fail = mode == :arm_error or (mode == :rearm_error and count == 2)
    {:reply, outcome(mode, fail, :arm), %{state | arms: count}}
  end

  def handle_call(:sync, _, state), do: {:reply, :ok, state}

  def handle_call(:close, _, state) do
    result =
      if state.config.options.mode == :close_error,
        do: {:error, Error.new(:cleanup_timeout)},
        else: outcome(state.config.options.mode, false, :close)

    {:stop, :normal, result, state}
  end

  @impl GenServer
  def handle_info({:emit, host, port, bytes}, state) do
    {:ok, host} = :inet.parse_address(String.to_charlist(host))
    Kernel.send(state.owner, {:wotex_datagram, state.config.generation, {:data, host, port, bytes}})
    {:noreply, state}
  end

  def handle_info({:emit, bytes}, state) do
    config = state.config

    Kernel.send(
      state.owner,
      {:wotex_datagram, config.generation, {:data, config.host, config.port, bytes}}
    )

    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}
end
