defimpl Inspect, for: Wotex.CoAP.Subscription do
  @moduledoc """
  Renders native CoAP subscription handles without exposing their fields.

  Every `Wotex.CoAP.Subscription` renders as the same opaque marker, regardless
  of its process, reference, generation, or request path. Routine inspection
  therefore cannot reveal routing or ownership state. Rendering performs no
  handle validation, process lookup, network operation, or cleanup; those
  responsibilities remain with the subscription and connection lifecycle.
  """

  @spec inspect(Wotex.CoAP.Subscription.t(), Inspect.Opts.t()) :: Inspect.Algebra.t()
  def inspect(_, _), do: "#Wotex.CoAP.Subscription<opaque>"
end
