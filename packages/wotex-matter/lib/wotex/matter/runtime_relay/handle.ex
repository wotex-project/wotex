defmodule Wotex.Matter.RuntimeRelay.Handle do
  @moduledoc """
  Identifies the owner and generation of a Matter Runtime subscription.

  `Wotex.Matter.Transport` returns this opaque handle after the relay binds its
  native subscription. Cancellation resolves through that relay and its original
  route; a later Form cannot redirect it. The live relay checks the generation
  before accepting cancellation. Its cleanup contract also covers handles whose
  owner has already ended.

  Inspection exposes only the generation. This value holds no credentials and
  starts no process when constructed or loaded.
  """

  @derive {Inspect, only: [:generation]}
  @enforce_keys [:pid, :generation]
  defstruct [:pid, :generation]

  @opaque t :: %__MODULE__{pid: pid(), generation: binary()}
end
