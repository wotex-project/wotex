defmodule Wotex.Matter.TestClient do
  @moduledoc false

  @behaviour Wotex.Matter.Client

  @impl Wotex.Matter.Client
  def connect(opts) do
    mode = Keyword.get(opts, :mode, :ok)

    if mode == :connect_error,
      do: {:error, :failed},
      else:
        {:ok,
         %{
           owner: self(),
           mode: mode,
           response: Keyword.get(opts, :response, :echo),
           secret: "fixture-secret"
         }}
  end

  @impl Wotex.Matter.Client
  def request(handle, message, timeout) do
    case handle.mode do
      :raise -> raise "private failure"
      :throw -> throw(:private)
      :exit -> exit(:private)
      :error -> {:error, :private}
      :typed -> {:error, Wotex.Matter.Error.new(:remote_error)}
      :invalid -> :unexpected
      _ -> response(handle, message, timeout)
    end
  end

  @impl Wotex.Matter.Client
  def disconnect(handle) do
    send(handle.owner, :disconnected)

    case handle.mode do
      :close_error -> {:error, :private}
      :close_invalid -> {:ok, :unexpected}
      _ -> :ok
    end
  end

  defp response(%{response: :echo}, message, _), do: {:ok, message}

  defp response(handle, message, timeout) do
    send(handle.owner, {:matter_request, message, timeout})
    {:ok, handle.response}
  end
end
