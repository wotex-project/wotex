defmodule Wotex.CoAP.RuntimeHandle do
  @moduledoc """
  Identifies one owned CoAP Runtime relay generation for bounded cleanup.

  The opaque value contains a local process identifier and a generation
  reference. Its internal identity check requires the exact struct shape and
  matches the generation against the relay's library-owned process marker.
  Self references, foreign live processes, and malformed handles are invalid;
  a dead relay is distinguished so repeated cleanup remains idempotent.

  `Wotex.CoAP.Transport` returns the value through the Runtime subscription
  lifecycle. Consumers pass it back unchanged rather than construct or persist
  it. Inspection omits both fields. The handle carries no credentials, native
  socket, payload, or execution context and does not authorize an interaction.
  """

  @derive {Inspect, only: []}
  @enforce_keys [:pid, :generation]
  defstruct [:pid, :generation]
  @opaque t :: %__MODULE__{pid: pid(), generation: reference()}

  @doc false
  @spec identity(term()) :: :owned | :closed | :invalid
  def identity(%__MODULE__{pid: pid, generation: generation} = handle)
      when map_size(handle) == 3 and is_pid(pid) and node(pid) == node() and pid != self() and
             is_reference(generation) do
    case :erlang.process_info(pid, {:dictionary, :wotex_coap_runtime_relay}) do
      :undefined -> :closed
      {{:dictionary, :wotex_coap_runtime_relay}, {Wotex.CoAP.RuntimeRelay, ^generation}} -> :owned
      _ -> :invalid
    end
  end

  def identity(_), do: :invalid
end
