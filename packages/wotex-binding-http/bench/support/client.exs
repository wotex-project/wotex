defmodule Wotex.Binding.HTTP.Bench.Client do
  @moduledoc false

  # In-memory client port. The client configuration maps each W3C WoT
  # operation to the callback return the client replays, so no request leaves
  # the VM. `{:raise, message}` raises instead, as a failing client would.

  @behaviour Wotex.Binding.HTTP.Client

  alias Wotex.Binding.HTTP.{Request, Response}

  @impl Wotex.Binding.HTTP.Client
  @spec request(Request.t(), term(), map()) :: {:ok, Response.t()} | {:error, term()}
  def request(request, _, replies), do: reply(replies, Request.operation(request))

  @impl Wotex.Binding.HTTP.Client
  @spec subscribe(Request.t(), term(), pid(), map()) ::
          {:ok, reference(), Response.t()} | {:error, term()}
  def subscribe(request, _, _, replies) do
    case reply(replies, Request.operation(request)) do
      {:ok, response} -> {:ok, make_ref(), response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Wotex.Binding.HTTP.Client
  @spec close(reference(), map()) :: :ok
  def close(_, _), do: :ok

  defp reply(replies, operation) do
    case Map.fetch!(replies, operation) do
      {:raise, message} -> raise message
      reply -> reply
    end
  end
end
