defmodule Wotex.BACnet.PortCall do
  @moduledoc false

  alias Wotex.BACnet.Error

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
