defmodule Wotex.BACnet.PortCall do
  @moduledoc """
  Normalizes calls across the consumer-selected BACnet client boundary.

  Tagged successes are preserved, and bare `:ok` is accepted only for disconnect
  and unsubscribe. Typed errors are normalized through `Wotex.BACnet.Error`;
  unknown return shapes, exceptions, exits, and throws become stable errors
  without retaining their original terms. Optional callbacks return
  `:not_supported` when absent.

  Invocation is synchronous and starts no timeout worker. Custom clients must
  honor their supplied budget and resource contract. Existing typed error
  details are not a general-purpose redaction boundary.
  """

  alias Wotex.BACnet.Error

  @doc false
  @spec optional(module(), atom(), [term()]) :: {:ok, term()} | :ok | {:error, Error.t()}
  def optional(module, function, arguments) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, function, length(arguments)) do
      invoke(module, function, arguments)
    else
      _ -> {:error, Error.new(:not_supported)}
    end
  end

  @doc false
  @spec invoke(module(), atom(), [term()]) :: {:ok, term()} | :ok | {:error, Error.t()}
  def invoke(module, function, args) do
    case apply(module, function, args) do
      {:ok, _} = result -> result
      :ok when function in [:disconnect, :unsubscribe] -> :ok
      {:error, %Error{} = error} -> {:error, Error.normalize(error)}
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
