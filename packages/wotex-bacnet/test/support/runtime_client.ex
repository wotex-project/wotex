defmodule Wotex.BACnet.Test.RuntimeClient do
  @moduledoc false

  @behaviour Wotex.BACnet.Client
  alias Wotex.BACnet.{Error, Subscription}

  @impl Wotex.BACnet.Client
  def connect(options) do
    owner = Keyword.fetch!(options, :test_owner)
    send(owner, {:native_connect, self()})

    case Keyword.get(options, :mode) do
      :failed -> {:error, Error.new(:startup_failed)}
      :blocked -> receive do: (:continue -> {:ok, owner})
      _ -> {:ok, owner}
    end
  end

  @impl Wotex.BACnet.Client
  def request(_, _, _), do: {:error, Error.new(:not_supported)}

  @impl Wotex.BACnet.Client
  def subscribe(owner, _, receiver, timeout) do
    child = spawn_link(fn -> receive do: (:stop -> :ok) end)

    subscription = %Subscription{
      pid: child,
      reference: make_ref(),
      generation: make_ref(),
      session_generation: make_ref()
    }

    send(owner, {:native_open, self(), receiver, subscription, timeout})

    receive do
      {:release, :ok} ->
        {:ok, subscription}

      {:release, :dead} ->
        monitor = Process.monitor(child)
        send(child, :stop)
        receive do: ({:DOWN, ^monitor, :process, ^child, _} -> {:ok, subscription})

      {:release, result} ->
        result
    end
  end

  @impl Wotex.BACnet.Client
  def unsubscribe(owner, subscription, timeout) do
    send(owner, {:native_cancel, self(), subscription, timeout})
    send(subscription.pid, :stop)
    :ok
  end

  @impl Wotex.BACnet.Client
  def disconnect(owner) do
    send(owner, {:native_disconnect, self()})
    :ok
  end
end
