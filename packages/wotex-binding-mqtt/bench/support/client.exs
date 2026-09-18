defmodule Wotex.Binding.MQTT.Bench.Client do
  @moduledoc false

  # In-memory client port. The client configuration maps each callback to the
  # return the client replays, so no command reaches a broker. `{:raise,
  # message}` raises instead, as a failing client would.

  @behaviour Wotex.Binding.MQTT.Client

  alias Wotex.Binding.MQTT.{Command, Delivery}
  alias Wotex.Runtime.ExecutionContext

  @impl Wotex.Binding.MQTT.Client
  @spec publish(Command.t(), ExecutionContext.t(), map()) :: term()
  def publish(_, _, replies), do: reply(replies, :publish)

  @impl Wotex.Binding.MQTT.Client
  @spec read(Command.t(), pos_integer(), ExecutionContext.t(), map()) ::
          {:ok, Delivery.t()} | {:error, term()}
  def read(_, _, _, replies), do: reply(replies, :read)

  @impl Wotex.Binding.MQTT.Client
  @spec subscribe(Command.t(), pid(), ExecutionContext.t(), map()) :: {:ok, reference()}
  def subscribe(_, _, _, _), do: {:ok, make_ref()}

  @impl Wotex.Binding.MQTT.Client
  @spec unsubscribe(reference(), Command.t(), ExecutionContext.t(), map()) :: :ok
  def unsubscribe(_, _, _, _), do: :ok

  defp reply(replies, callback) do
    case Map.fetch!(replies, callback) do
      {:raise, message} -> raise message
      reply -> reply
    end
  end
end
