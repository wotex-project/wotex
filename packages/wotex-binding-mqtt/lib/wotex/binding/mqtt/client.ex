defmodule Wotex.Binding.MQTT.Client do
  @moduledoc """
  Consumer-supplied MQTT client port.

  The implementation owns connection lifecycle and MQTT session state. Its
  configuration and returned handles must be credential-free. Credentials are
  available only through the execution context during an immediate callback and
  must not be retained.
  """

  alias Wotex.Binding.MQTT.{Command, Delivery, Error}
  alias Wotex.Runtime.ExecutionContext

  @type config :: term()
  @type handle :: term()
  @type delivery_callback :: (Delivery.t() -> :ok | {:error, Error.t()})

  @doc "Publishes the command's encoded JSON Application Message."
  @callback publish(Command.t(), ExecutionContext.t(), config()) :: :ok | {:error, term()}

  @doc "Performs a finite read and returns one MQTT delivery."
  @callback read(Command.t(), pos_integer(), ExecutionContext.t(), config()) ::
              {:ok, Delivery.t()} | {:error, term()}

  @doc "Subscribes and invokes the delivery callback for each MQTT delivery."
  @callback subscribe(Command.t(), delivery_callback(), ExecutionContext.t(), config()) ::
              {:ok, handle()} | {:error, term()}

  @doc "Unsubscribes a caller-owned client handle."
  @callback unsubscribe(handle(), Command.t(), ExecutionContext.t(), config()) ::
              :ok | {:error, term()}
end
