defmodule Wotex.Matter.RuntimeRelay.Handle do
  @moduledoc false

  @derive {Inspect, only: [:generation]}
  @enforce_keys [:pid, :generation]
  defstruct [:pid, :generation]

  @opaque t :: %__MODULE__{pid: pid(), generation: binary()}
end
