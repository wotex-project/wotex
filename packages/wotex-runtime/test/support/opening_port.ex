defmodule Wotex.Runtime.Test.OpeningPort do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials
  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Credentials
  def resolve(_ignored_1, _ignored_2, _ignored_3, config) do
    if config[:credential_wait] do
      send(config.test_pid, {:credential_wait, self()})

      receive do
        :release -> :ok
      end
    end

    {:ok, "OPENING_CREDENTIAL_CANARY"}
  end

  @impl Wotex.Runtime.Transport
  def subscribe(_ignored_4, owner, _ignored_5, config) do
    resource = spawn_link(fn -> resource(owner, config) end)
    send(config.test_pid, {:opening, self(), owner, resource})

    for value <- Map.get(config, :early, []),
        do: send(owner, {:wotex_transport_frame, {:value, value}})

    receive do
      :release -> {:ok, resource}
    end
  end

  @impl Wotex.Runtime.Transport
  def unsubscribe(resource, _ignored_6, _ignored_7, config) do
    send(config.test_pid, {:opening_unsubscribe, resource})
    send(resource, :stop)
    :ok
  end

  @impl Wotex.Runtime.Transport
  def request(_ignored_8, _ignored_9, _ignored_10), do: {:error, :not_supported}

  @impl Wotex.Runtime.Transport
  def decode_frame({:value, value}, _ignored_11, config) do
    send(config.test_pid, {:opening_decoded, self(), value})
    {:ok, value, %{source: :opening_fixture}}
  end

  defp resource(owner, config) do
    ref = if Map.get(config, :monitor_owner, true), do: Process.monitor(owner), else: make_ref()
    send(config.test_pid, {:resource_started, self()})

    receive do
      {:DOWN, ^ref, :process, ^owner, _ignored_12} -> :ok
      :stop -> :ok
    end
  end
end
