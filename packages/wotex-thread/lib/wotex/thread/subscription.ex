defmodule Wotex.Thread.Subscription do
  @moduledoc """
  Identifies one native State subscription of an owned OpenThread session.

  The handle names the session owner process, an opaque reference and the
  native stream generation. It carries no receiver, configuration or network
  data, and inspection shows only the generation. Deliveries arrive as
  `{:wotex_thread, reference, {:ok, %Wotex.Thread.State{}, %{changed_flags: flags}}}`
  or one terminal `{:wotex_thread, reference, {:error, %Wotex.Thread.Error{}}}`.
  """

  @derive {Inspect, only: [:generation]}
  @enforce_keys [:pid, :reference, :generation]
  defstruct @enforce_keys

  @typedoc "An opaque, generation-bound State subscription handle."
  @type t :: %__MODULE__{pid: pid(), reference: reference(), generation: pos_integer()}

  @doc "Validates the exact field types of a handle without contacting its owner."
  @spec validate(term()) :: :ok | {:error, Wotex.Thread.Error.t()}
  def validate(%__MODULE__{pid: pid, reference: reference, generation: generation} = handle)
      when map_size(handle) == 4 and is_pid(pid) and node(pid) == node() and
             is_reference(reference) and is_integer(generation) and
             generation in 1..0xFFFFFFFFFFFFFFFE,
      do: :ok

  def validate(_), do: {:error, Wotex.Thread.Error.new(:invalid_subscription)}
end
