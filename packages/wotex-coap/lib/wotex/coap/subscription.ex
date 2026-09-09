defmodule Wotex.CoAP.Subscription do
  @moduledoc """
  Identifies one explicitly established observation on a connection generation.

  Construction and validation are pure shape checks. The connection owner must
  additionally verify the live reference and generation before cancellation.
  Inspection does not expose the handle's process or reference identities.
  """

  alias Wotex.CoAP.Error
  @enforce_keys [:pid, :reference, :generation]
  defstruct [:pid, :reference, :generation]

  @opaque t :: %__MODULE__{pid: pid(), reference: reference(), generation: reference()}

  @doc "Constructs an opaque local handle without contacting its process."
  @spec new(pid(), reference(), reference()) :: {:ok, t()} | {:error, Error.t()}
  def new(pid, reference, generation)
      when is_pid(pid) and node(pid) == node() and is_reference(reference) and
             is_reference(generation),
      do: {:ok, %__MODULE__{pid: pid, reference: reference, generation: generation}}

  def new(_, _, _), do: {:error, Error.new(:invalid_subscription)}

  @doc "Checks exact handle shape and its association with the supplied local session."
  @spec validate(term(), pid()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{pid: pid, reference: reference, generation: generation} = handle, pid)
      when map_size(handle) == 4 and is_pid(pid) and node(pid) == node() and
             is_reference(reference) and is_reference(generation),
      do: :ok

  def validate(_, _), do: {:error, Error.new(:invalid_subscription)}
end
