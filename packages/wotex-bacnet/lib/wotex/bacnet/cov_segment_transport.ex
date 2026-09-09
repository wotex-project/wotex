defmodule Wotex.BACnet.COVSegmentTransport do
  @moduledoc """
  Adapts COV reassembly destinations to the pinned BACstack transport.

  COV assemblies use a tagged source containing the transport module and actual
  source. This keeps their segment-store identity separate from ordinary
  confirmed exchanges. The adapter unwraps that identity for destination
  validation and SegmentACK transmission through the original transport.

  `Wotex.BACnet.StackCOV` constructs these internal destinations. This module
  owns no transport and performs no independent validation of an arbitrary
  module supplied by a caller.
  """

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
