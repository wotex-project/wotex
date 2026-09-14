defmodule Wotex.Binding.MQTT.Test.LifecycleClient do
  @moduledoc false

  @behaviour Wotex.Binding.MQTT.Client

  alias Wotex.Binding.MQTT.{Command, Delivery}

  @spec start_link(pid()) :: Agent.on_start()
  def start_link(test_pid) do
    Agent.start_link(fn ->
      %{test_pid: test_pid, next_handle: 1, active: %{}, close_attempts: %{}}
    end)
  end

  @spec snapshot(pid()) :: map()
  def snapshot(state), do: Agent.get(state, & &1)

  @impl Wotex.Binding.MQTT.Client
  def publish(_, _, config),
    do: Map.get(config, :publish_return, :ok)

  @impl Wotex.Binding.MQTT.Client
  def read(command, timeout, _, config) do
    send(config.test_pid, {:lifecycle_read, timeout, Command.filters(command)})

    case Map.get(config, :read_mode, {:error, :no_delivery}) do
      {:delay, delay, %Delivery{} = delivery} when delay <= timeout ->
        Process.sleep(delay)
        {:ok, delivery}

      {:delay, _, %Delivery{}} ->
        Process.sleep(timeout)
        {:error, :timeout}

      return ->
        return
    end
  end

  @impl Wotex.Binding.MQTT.Client
  def subscribe(command, owner, _, config) do
    send(config.test_pid, {:lifecycle_subscribe_attempt, owner, Command.filters(command)})

    case Map.get(config, :subscribe_return, :ok) do
      :ok ->
        handle =
          Agent.get_and_update(config.state, fn state ->
            handle = {:consumer_handle, state.next_handle}
            active = Map.put(state.active, handle, owner)
            {handle, %{state | next_handle: state.next_handle + 1, active: active}}
          end)

        send(config.test_pid, {:lifecycle_subscribed, handle, owner})
        {:ok, handle}

      return ->
        return
    end
  end

  @impl Wotex.Binding.MQTT.Client
  def unsubscribe(handle, command, _, config) do
    {owner, close_count} =
      Agent.get_and_update(config.state, fn state ->
        owner = Map.get(state.active, handle)
        close_attempts = Map.update(state.close_attempts, handle, 1, &(&1 + 1))

        next_state =
          case Map.get(config, :unsubscribe_return, :ok) do
            :ok ->
              %{state | active: Map.delete(state.active, handle), close_attempts: close_attempts}

            _ ->
              %{state | close_attempts: close_attempts}
          end

        {{owner, Map.fetch!(close_attempts, handle)}, next_state}
      end)

    send(
      config.test_pid,
      {:lifecycle_unsubscribe_attempt, handle, owner, close_count, Command.filters(command)}
    )

    Map.get(config, :unsubscribe_return, :ok)
  end
end
