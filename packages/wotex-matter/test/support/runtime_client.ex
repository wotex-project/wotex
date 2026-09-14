defmodule Wotex.Matter.RuntimeClient do
  @moduledoc false

  @behaviour Wotex.Matter.Client

  @impl Wotex.Matter.Client
  def connect(options) do
    test_pid = Keyword.fetch!(options, :test_pid)
    send(test_pid, {:matter_connect, self()})

    case Keyword.get(options, :connect_error) do
      %Wotex.Matter.Error{} = error ->
        {:error, error}

      nil ->
        {:ok,
         %{
           test_pid: test_pid,
           response: Keyword.get(options, :response, :unused),
           opening_deliveries: Keyword.get(options, :opening_deliveries, [])
         }}
    end
  end

  @impl Wotex.Matter.Client
  def request(handle, message, timeout) do
    send(handle.test_pid, {:matter_request, message, timeout})

    case handle.response do
      {:error, %Wotex.Matter.Error{}} = error -> error
      response -> {:ok, response}
    end
  end

  @impl Wotex.Matter.Client
  def subscribe(handle, request, receiver, timeout) do
    reference = make_ref()
    subscription = %Wotex.Matter.Subscription{pid: self(), reference: reference, generation: 1}
    send(handle.test_pid, {:matter_subscribe, self(), receiver, request, timeout, reference})
    Enum.each(handle.opening_deliveries, &send(receiver, {:wotex_matter, reference, &1}))
    {:ok, subscription}
  end

  @impl Wotex.Matter.Client
  def unsubscribe(handle, subscription, timeout) do
    send(handle.test_pid, {:matter_unsubscribe, self(), subscription, timeout})
    :ok
  end

  @impl Wotex.Matter.Client
  def disconnect(handle) do
    send(handle.test_pid, :disconnected)
    :ok
  end
end
