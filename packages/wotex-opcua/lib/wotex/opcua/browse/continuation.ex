defmodule Wotex.OPCUA.Browse.Continuation do
  @moduledoc """
  Identifies one live Browse page cursor on its original native Session.

  The server's opaque bytes remain inside the native owner. Inspection omits
  the generation and reference; a consumed or foreign handle cannot be reused.
  """

  @derive {Inspect, only: [:pid]}
  @enforce_keys [:pid, :reference, :generation]
  defstruct [:pid, :reference, :generation]

  @type t :: %__MODULE__{pid: pid(), reference: reference(), generation: pos_integer()}
end
