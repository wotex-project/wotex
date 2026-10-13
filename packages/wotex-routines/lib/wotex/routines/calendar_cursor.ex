defmodule Wotex.Routines.CalendarCursor do
  @moduledoc "Opaque native SP.08 continuation bound to the adapter's schedule/query and clock projection. No processing proof."

  @enforce_keys [:basis_digest, :clock_generation, :producer_cursor]
  defstruct [:basis_digest, :clock_generation, :producer_cursor]

  @type t :: %__MODULE__{
          basis_digest: String.t(),
          clock_generation: String.t(),
          producer_cursor: term()
        }
end
