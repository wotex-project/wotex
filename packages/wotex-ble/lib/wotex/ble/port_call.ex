defmodule Wotex.BLE.PortCall do
  @moduledoc """
  Normalizes synchronous calls to a selected BLE client implementation.

  This implementation helper accepts tagged success, typed `Wotex.BLE.Error`
  failures and `:ok` from disconnect. Invalid returns, untyped errors, raised
  exceptions, exits and throws become stable transport errors without carrying
  external exception text. Typed errors receive the package classification;
  unknown mutation effect always disables retry and becomes permanent.

  Calls run in the invoking process. The helper starts no worker and adds no
  deadline; the client must enforce the supplied timeout. Typed diagnostic
  details are preserved, so client authors must exclude secrets and bound them.
  The facade separately applies conservative write-effect handling.
  """

  alias Wotex.BLE.Error

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
