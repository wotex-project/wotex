defmodule Wotex.Matter.TestClient do
  @moduledoc false

  @behaviour Wotex.Matter.Client

  @impl Wotex.Matter.Client
  def connect(opts) do
    mode = Keyword.get(opts, :mode, :ok)

    if mode == :connect_error,
      do: {:error, :failed},
      else: {:ok, %{owner: self(), mode: mode, secret: "fixture-secret"}}
  end

  @impl Wotex.Matter.Client
  def request(handle, message, _) do
    case handle.mode do
      :raise -> raise "private failure"
      :throw -> throw(:private)
      :exit -> exit(:private)
      :error -> {:error, :private}
      :typed -> {:error, Wotex.Matter.Error.new(:remote_error)}
      :invalid -> :unexpected
      _ -> {:ok, message}
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
end
