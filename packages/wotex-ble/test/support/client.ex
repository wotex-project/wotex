defmodule Wotex.BLE.TestClient do
  @moduledoc false

  @behaviour Wotex.BLE.Client

  @impl Wotex.BLE.Client
  def connect(opts) do
    mode = Keyword.get(opts, :mode, :ok)

    case mode do
      :connect_error -> {:error, :failed}
      :connect_invalid -> :unexpected
      _ -> {:ok, %{owner: self(), mode: mode, secret: "fixture-secret"}}
    end
  end

  @impl Wotex.BLE.Client
  def request(handle, message, _) do
    case handle.mode do
      :raise -> raise "private failure"
      :throw -> throw(:private)
      :exit -> exit(:private)
      :error -> {:error, :private}
      :bytes -> {:ok, <<42>>}
      :typed -> {:error, Wotex.BLE.Error.new(:remote_error)}
      :invalid -> :unexpected
      _ -> {:ok, message}
    end
  end

  @impl Wotex.BLE.Client
  def disconnect(handle) do
    send(handle.owner, :disconnected)

    case handle.mode do
      :close_error -> {:error, :private}
      :close_invalid -> {:ok, :unexpected}
      _ -> :ok
    end
  end
end
