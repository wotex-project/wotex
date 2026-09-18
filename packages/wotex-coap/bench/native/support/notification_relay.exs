defmodule Wotex.CoAP.Bench.NotificationRelay do
  @moduledoc false

  # The receiver of a benchmarked subscription. Benchee runs each job in its
  # own process, so a job registers the payload it waits for here before it
  # changes the resource, and the relay answers when that notification arrives.

  @doc "Starts a relay linked to the caller."
  @spec start_link() :: pid()
  def start_link, do: spawn_link(fn -> loop(%{}) end)

  @doc "Registers the caller as the waiter for a notification carrying `payload`."
  @spec expect(pid(), binary()) :: :ok
  def expect(relay, payload) do
    send(relay, {:expect, self(), payload})
    :ok
  end

  @doc "Waits for the notification registered with `expect/2`."
  @spec await(binary(), timeout()) :: :ok
  def await(payload, timeout) do
    receive do
      {:notified, ^payload} -> :ok
    after
      timeout -> raise "no notification carrying #{byte_size(payload)} bytes"
    end
  end

  defp loop(waiters) do
    receive do
      {:expect, from, payload} ->
        loop(Map.put(waiters, payload, from))

      {:wotex_coap, _, {:ok, %Wotex.CoAP.Message{payload: payload}, _}} ->
        {from, waiters} = Map.pop(waiters, payload)
        if from, do: send(from, {:notified, payload})
        loop(waiters)

      {:wotex_coap, _, other} ->
        raise "unexpected observation result #{inspect(other)}"
    end
  end
end
