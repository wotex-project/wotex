defmodule Wotex.Binding.HTTP.Test.FakeClient do
  @moduledoc false

  @behaviour Wotex.Binding.HTTP.Client

  @impl Wotex.Binding.HTTP.Client
  @spec request(term(), term(), map()) :: term()
  def request(request, credential, config) do
    send(config.owner, {:client_request, request, credential})
    return(config, :request_return, {:error, :not_configured})
  end

  @impl Wotex.Binding.HTTP.Client
  @spec subscribe(term(), term(), pid(), map()) :: term()
  def subscribe(request, credential, owner, config) do
    send(config.owner, {:client_subscribe, request, credential, owner})
    if Map.get(config, :monitor_owner, false), do: watch_owner(owner, config.owner)
    if Map.get(config, :link_owner, false), do: link_owner(owner, config.owner)
    for frame <- Map.get(config, :frames, []), do: send(owner, {:wotex_transport_frame, frame})
    return(config, :subscribe_return, {:error, :not_configured})
  end

  @impl Wotex.Binding.HTTP.Client
  @spec close(term(), map()) :: term()
  def close(handle, config) do
    send(config.owner, {:client_close, handle})
    return(config, :close_return, :ok)
  end

  defp watch_owner(owner, observer) do
    spawn(fn ->
      reference = Process.monitor(owner)

      receive do
        {:DOWN, ^reference, :process, ^owner, reason} -> send(observer, {:owner_down, reason})
      end
    end)
  end

  defp link_owner(owner, observer) do
    spawn_link(fn ->
      reference = Process.monitor(owner)
      send(observer, {:client_connection, self()})

      receive do
        {:fail, reason} -> exit(reason)
        {:DOWN, ^reference, :process, ^owner, _} -> :ok
      end
    end)
  end

  defp return(config, key, default) do
    case Map.get(config, key, default) do
      {:raise, exception} -> raise exception
      {:exit, reason} -> exit(reason)
      {:throw, value} -> throw(value)
      fun when is_function(fun, 0) -> fun.()
      value -> value
    end
  end
end
