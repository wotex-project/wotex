defmodule Wotex.Matter.Subscription do
  @moduledoc """
  Opaque handle for one established Matter attribute or event subscription.

  A handle is valid only for the owning connection process and delivery
  generation. Its process identity and reference are intentionally omitted
  from inspection output. Use `Wotex.Matter.unsubscribe/2` for cleanup.
  """

  @derive {Inspect, only: [:generation]}
  @enforce_keys [:pid, :reference, :generation]
  defstruct [:pid, :reference, :generation]

  @type t :: %__MODULE__{
          pid: pid(),
          reference: reference(),
          generation: pos_integer()
        }
end
