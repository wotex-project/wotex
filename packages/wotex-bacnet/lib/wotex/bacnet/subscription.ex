defmodule Wotex.BACnet.Subscription do
  @moduledoc "A redacted handle bound to a subscription owner and its original session."

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
