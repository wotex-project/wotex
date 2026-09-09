defmodule Wotex.BACnet.RuntimeHandle do
  @moduledoc """
  Opaque identity for a BACnet observation relay owned by Runtime.

  The value combines a process identifier with a fresh generation reference.
  `Wotex.BACnet.RuntimeRelay` verifies that generation before closing a live
  relay. Inspection omits both fields so the handle is not presented as a
  portable or serializable address.

  Shape validation alone proves neither liveness nor ownership. Consumers
  receive this value through the transport boundary and must return it intact;
  it is distinct from the native `Wotex.BACnet.Subscription` handle.
  """

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
