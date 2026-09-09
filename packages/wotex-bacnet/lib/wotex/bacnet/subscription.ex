defmodule Wotex.BACnet.Subscription do
  @moduledoc """
  Redacted handle bound to a Change of Value subscription and its original session.

  The handle carries the owner PID, an opaque subscription reference, and
  generation references for both the listener and session. These fields let the
  BACnet transport reject stale, forged, or cross-session cancellation attempts
  without exposing device addresses, credentials, queue contents, or protocol
  state through inspection.

  Consumers treat the struct as opaque and return it to the matching close
  operation. `valid?/1` checks only its field types; live ownership, generation,
  and session identity are verified by the persistent subscription owner before
  any protocol request is issued.
  """

  @enforce_keys [:pid, :reference, :generation, :session_generation]
  @derive {Inspect, only: []}
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          pid: pid(),
          reference: reference(),
          generation: reference(),
          session_generation: reference()
        }

  @doc "Checks handle field types without consulting processes or issuing protocol requests."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{
        pid: pid,
        reference: ref,
        generation: generation,
        session_generation: session
      }),
      do: is_pid(pid) and is_reference(ref) and is_reference(generation) and is_reference(session)

  def valid?(_), do: false
end
