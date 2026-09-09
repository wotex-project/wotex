defmodule Wotex.Runtime.Test.OpeningPort do
  @moduledoc false

  @behaviour Wotex.Runtime.Credentials
  @behaviour Wotex.Runtime.Transport

  @impl Wotex.Runtime.Credentials
  def resolve(_, _, _, config) do
    if config[:credential_wait] do
      send(config.test_pid, {:credential_wait, self()})

      receive do
        :release -> :ok
      end
    end

    {:ok, "OPENING_CREDENTIAL_CANARY"}
  end

  @impl Wotex.Runtime.Transport
  def subscribe(_, owner, _, config) do
    resource = spawn_link(fn -> resource(owner, config) end)
    send(config.test_pid, {:opening, self(), owner, resource})

    for value <- Map.get(config, :early, []),
        do: send(owner, {:wotex_transport_frame, {:value, value}})

    receive do
      :release ->
        {:ok, resource}

      {:reject, error} ->
        monitor = Process.monitor(resource)
        Process.exit(resource, :shutdown)

        receive do
          {:DOWN, ^monitor, :process, ^resource, :shutdown} -> {:error, error}
        end
    end
  end

  @impl Wotex.Runtime.Transport
  def unsubscribe(resource, _, _, config) do
    send(config.test_pid, {:opening_unsubscribe, resource})
    send(resource, :stop)
    :ok
  end

  @impl Wotex.Runtime.Transport
  def request(_, _, _), do: {:error, :not_supported}

  @impl Wotex.Runtime.Transport
  def decode_frame({:value, value}, _, config) do
    send(config.test_pid, {:opening_decoded, self(), value})
    {:ok, value, %{source: :opening_fixture}}
  end

  defp resource(owner, config) do
    ref = if Map.get(config, :monitor_owner, true), do: Process.monitor(owner), else: make_ref()
    send(config.test_pid, {:resource_started, self()})

    receive do
      {:DOWN, ^ref, :process, ^owner, _} -> :ok
      :stop -> :ok
    end
  end
end
