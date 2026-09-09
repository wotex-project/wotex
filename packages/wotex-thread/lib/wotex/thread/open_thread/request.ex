defmodule Wotex.Thread.OpenThread.Request do
  @moduledoc false

  alias Wotex.Thread.Error
  alias Wotex.Thread.OpenThread.DatasetWire

  @doc false
  @spec encode(term()) :: {:ok, {String.t(), map()}} | {:error, Error.t()}
  def encode(%{type: type} = request)
      when map_size(request) == 1 and type in [:inspect, :state, :version, :network_name, :rloc16],
      do: {:ok, {Atom.to_string(type), %{}}}

  def encode(%{type: :validate_dataset, dataset: dataset, kind: kind} = request)
      when map_size(request) == 3 do
    with {:ok, parameters} <- DatasetWire.parameters(dataset, kind),
         do: {:ok, {"validate_dataset", parameters}}
  end

  def encode(%{type: :get_dataset, kind: kind} = request) when map_size(request) == 2 do
    with {:ok, parameters} <- DatasetWire.selector(kind), do: {:ok, {"get_dataset", parameters}}
  end

  def encode(_), do: {:error, Error.new(:invalid_message)}
end
