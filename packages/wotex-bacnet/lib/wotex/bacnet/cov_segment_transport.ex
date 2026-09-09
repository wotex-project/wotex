defmodule Wotex.BACnet.COVSegmentTransport do
  @moduledoc false

  @doc false
  @spec is_valid_destination(term()) :: boolean()
  # Pinned SDK transport callback spelling.
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_valid_destination({:cov, module, source}), do: module.is_valid_destination(source)

  @doc false
  @spec send(term(), term(), term(), keyword()) :: term()
  def send(portal, {:cov, module, source}, apdu, options),
    do: module.send(portal, source, apdu, options)
end
