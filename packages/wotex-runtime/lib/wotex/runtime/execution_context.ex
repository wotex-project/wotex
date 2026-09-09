defmodule Wotex.Runtime.ExecutionContext do
  @moduledoc """
  Ephemeral context passed only across an immediate port call.

  Credential material is omitted from inspection and must not be retained by a
  transport after the call requiring it.

  A `t:t/0` combines the public `Wotex.Runtime.Context` with the credential
  returned by the consumer's credential port for one immediate transport call.
  Runtime creates the value only after Form selection and credential
  resolution, then passes it to the selected `Wotex.Runtime.Transport`.

  The struct is deliberately not a general configuration or process state. Its
  inspection representation exposes only the non-secret context. Transports
  may apply the credential to their direct client call, but must not copy it
  into requests, responses, errors, subscription handles, telemetry, logs, or
  long-lived closures. Possessing an execution context does not grant authority
  beyond the consumer decision that created it.
  """

  alias Wotex.Runtime.Context

  @derive {Inspect, only: [:context]}
  @type t :: %__MODULE__{context: Context.t(), credential: term()}
  @enforce_keys [:context, :credential]
  defstruct [:context, :credential]

  @doc false
  @spec new(Context.t(), term()) :: t()
  def new(%Context{} = context, credential),
    do: %__MODULE__{context: context, credential: credential}
end
