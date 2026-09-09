defmodule Wotex.BACnet.RuntimeHandle do
  @moduledoc false

  @derive {Inspect, only: []}
  @enforce_keys [:pid, :generation]
  defstruct [:pid, :generation]
  @type t :: %__MODULE__{pid: pid(), generation: reference()}

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{pid: pid, generation: generation}),
    do: is_pid(pid) and is_reference(generation)

  def valid?(_), do: false
end
