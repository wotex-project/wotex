defmodule Wotex.Matter.PortCall do
  @moduledoc """
  Normalizes synchronous calls to the selected Matter client implementation.

  This implementation helper accepts tagged success, a typed
  `Wotex.Matter.Error`, or `:ok` from disconnect. Other return shapes and untyped
  errors become stable transport errors. Raised exceptions, exits and throws
  are converted without retaining their external messages or stack traces.

  Calls run in the invoking process. The helper does not start a worker or
  enforce a deadline; the selected client must honor the timeout supplied to
  its request callback. The facade separately marks failed writes and invokes
  with unknown effect. Existing typed errors are preserved, so client authors
  remain responsible for excluding secrets and bounding diagnostic details.
  """

  alias Wotex.Matter.Error

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
