defimpl Inspect, for: Wotex.CoAP.Subscription do
  @moduledoc false

  @spec inspect(Wotex.CoAP.Subscription.t(), Inspect.Opts.t()) :: Inspect.Algebra.t()
  def inspect(_, _), do: "#Wotex.CoAP.Subscription<opaque>"
end
