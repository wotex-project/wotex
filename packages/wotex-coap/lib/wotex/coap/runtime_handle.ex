defmodule Wotex.CoAP.RuntimeHandle do
  @moduledoc false

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
