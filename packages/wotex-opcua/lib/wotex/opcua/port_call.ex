defmodule Wotex.OPCUA.PortCall do
  @moduledoc """
  Normalizes calls to the consumer-selected OPC UA client implementation.

  The facade and session use this synchronous boundary to invoke client
  callbacks. It preserves `{:ok, value}` and typed `Wotex.OPCUA.Error` results,
  accepts bare `:ok` only for disconnect, and converts other return shapes,
  exceptions, exits, and throws into stable errors without their original terms.

  This helper does not start a worker or enforce a callback deadline. The
  selected client must honor the supplied timeout and own its resources.
  `Wotex.OPCUA.Open62541` uses an owned C executable; the older
  `Wotex.OPCUA.Asyncua` implementation uses a Python bridge.
  """

  alias Wotex.OPCUA.Error

  @doc false
  @spec invoke(module(), atom(), [term()]) :: {:ok, term()} | :ok | {:error, Error.t()}
  def invoke(module, function, args) do
    case apply(module, function, args) do
      {:ok, _} = result -> result
      :ok when function == :disconnect -> :ok
      {:error, %Error{}} = result -> result
      {:error, _} -> {:error, Error.new(:transport_error)}
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  rescue
    _ -> {:error, Error.new(:transport_exception)}
  catch
    :exit, _ -> {:error, Error.new(:transport_exit)}
    :throw, _ -> {:error, Error.new(:transport_throw)}
  end
end
