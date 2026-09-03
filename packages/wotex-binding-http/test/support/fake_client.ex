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
  @spec subscribe(term(), term(), function(), map()) :: term()
  def subscribe(request, credential, handler, config) do
    send(config.owner, {:client_subscribe, request, credential, handler})
    return(config, :subscribe_return, {:error, :not_configured})
  end

  @impl Wotex.Binding.HTTP.Client
  @spec close(term(), map()) :: term()
  def close(handle, config) do
    send(config.owner, {:client_close, handle})
    return(config, :close_return, :ok)
  end

  defp return(config, key, default) do
    case Map.get(config, key, default) do
      {:raise, exception} -> raise exception
      fun when is_function(fun, 0) -> fun.()
      value -> value
    end
  end
end
