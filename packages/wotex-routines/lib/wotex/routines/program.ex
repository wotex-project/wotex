defmodule Wotex.Routines.Program do
  @moduledoc "Complete source/context and regenerated immutable IR. A program carries no execution authority."

  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}
end
