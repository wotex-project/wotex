defmodule Wotex.Runtime.ExecutionContext do
  @moduledoc """
  Ephemeral context passed only across an immediate port call.

  Credential material is omitted from inspection and must not be retained by a
  transport after the call requiring it.
  """

  alias Wotex.Runtime.Context

  @derive {Inspect, only: [:context]}
  @opaque t :: %__MODULE__{context: Context.t(), credential: term()}
  @enforce_keys [:context, :credential]
  defstruct [:context, :credential]

  @doc false
  @spec new(Context.t(), term()) :: t()
  def new(%Context{} = context, credential),
    do: %__MODULE__{context: context, credential: credential}
end
