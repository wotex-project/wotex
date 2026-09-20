defmodule Wotex.Thread.PortCall do
  @moduledoc """
  Normalizes calls to a Thread client port.

  This internal boundary converts client callback failures, invalid return
  values, exceptions, exits, and throws into `Wotex.Thread.Error` values so
  callers do not depend on client-specific failure shapes.
  """

  alias Wotex.Thread.Error

  @doc false
  @spec invoke(module(), atom(), [term()]) :: {:ok, term()} | :ok | {:error, Error.t()}
  def invoke(module, function, args) do
    case apply(module, function, args) do
      {:ok, _} = result -> result
      :ok when function == :disconnect -> :ok
      {:error, %Error{} = error} -> {:error, Error.classify(error)}
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
