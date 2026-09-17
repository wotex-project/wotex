defmodule Wotex.OPCUA.TestStreamClient do
  @moduledoc false

  @behaviour Wotex.OPCUA.Client
  alias Wotex.OPCUA.{Error, Subscription}

  @impl Wotex.OPCUA.Client
  def connect(opts) do
    test = Keyword.fetch!(opts, :test)
    mode = Keyword.get(opts, :mode, :ok)
    send(test, {:stream_connected, self(), Keyword.fetch!(opts, :timeout)})
    if mode == :slow_connect, do: Process.sleep(60)

    if mode == :connect_error,
      do: {:error, Error.new(:connection_failed)},
      else: {:ok, %{test: test, mode: mode}}
  end

  @impl Wotex.OPCUA.Client
  def request(_, message, _), do: {:ok, message}

  @impl Wotex.OPCUA.Client
  def disconnect(handle) do
    send(handle.test, {:stream_disconnected, self()})
    if handle.mode == :disconnect_error, do: {:error, Error.new(:cleanup_failed)}, else: :ok
  end

  @impl Wotex.OPCUA.Client
  def subscribe(handle, request, receiver, _) do
    case handle.mode do
      :subscribe_error ->
        {:error, Error.new(:remote_error)}

      :block ->
        send(handle.test, {:stream_blocked, self()})

        receive do
          :never -> {:error, Error.new(:remote_error)}
        end

      _ ->
        subscription = %Subscription{pid: self(), reference: make_ref(), generation: 1}
        send(handle.test, {:stream_subscribed, receiver, subscription, request})
        {:ok, subscription}
    end
  end

  @impl Wotex.OPCUA.Client
  def unsubscribe(handle, subscription, _) do
    send(handle.test, {:stream_unsubscribed, subscription.reference})
    if handle.mode == :unsubscribe_error, do: {:error, Error.new(:cleanup_failed)}, else: :ok
  end
end
