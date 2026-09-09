defmodule Wotex.BLE.Subscription do
  @moduledoc """
  Identifies one explicitly established native value-change subscription.

  The owning connection supplies the process, reference and generation only
  after BlueZ acknowledges StartNotify. A separate session reference binds the
  handle to its originating connection generation. Handles carry no value,
  credentials or receiver policy. Inspect omits both references. Construction alone establishes
  no subscription; the owner validates membership before cancellation.
  """

  @derive {Inspect, only: [:pid, :generation]}
  @enforce_keys [:pid, :reference, :generation, :session_reference]
  defstruct [:pid, :reference, :generation, :session_reference]

  @typedoc "An opaque reference to one subscription in its owning connection generation."
  @opaque t :: %__MODULE__{
            pid: pid(),
            reference: reference(),
            generation: pos_integer(),
            session_reference: reference()
          }
end
