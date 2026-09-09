defmodule Wotex.Binding.MQTT.Test.FakeClient do
  @moduledoc false

  @behaviour Wotex.Binding.MQTT.Client

  @impl Wotex.Binding.MQTT.Client
  def publish(command, execution_context, config) do
    send(config.test_pid, {:client_publish, command, execution_context, config.client_marker})
    client_return(config, :publish_return, :ok)
  end

  @impl Wotex.Binding.MQTT.Client
  def read(command, timeout, execution_context, config) do
    send(
      config.test_pid,
      {:client_read, command, timeout, execution_context, config.client_marker}
    )

    client_return(config, :read_return, {:error, :missing_test_delivery})
  end

  @impl Wotex.Binding.MQTT.Client
  def subscribe(command, owner, execution_context, config) do
    watch_owner(owner, config)

    send(
      config.test_pid,
      {:client_subscribe, command, owner, execution_context, config.client_marker}
    )

    client_return(config, :subscribe_return, {:ok, :client_handle})
  end

  @impl Wotex.Binding.MQTT.Client
  def unsubscribe(handle, command, execution_context, config) do
    send(
      config.test_pid,
      {:client_unsubscribe, handle, command, execution_context, config.client_marker}
    )

    client_return(config, :unsubscribe_return, :ok)
  end

  defp watch_owner(owner, %{watch_owner: true, test_pid: test_pid}) do
    subscriber = self()

    watcher =
      spawn(fn ->
        reference = Process.monitor(owner)
        send(subscriber, {:owner_watched, self()})

        receive do
          {:DOWN, ^reference, :process, ^owner, reason} -> send(test_pid, {:owner_down, reason})
        end
      end)

    receive do
      {:owner_watched, ^watcher} -> :ok
    end
  end

  defp watch_owner(_, _), do: :ok

  defp client_return(config, key, default) do
    case Map.get(config, key, default) do
      :raise -> raise "external client failure"
      :throw -> throw(:external_client_failure)
      value -> value
    end
  end
end
