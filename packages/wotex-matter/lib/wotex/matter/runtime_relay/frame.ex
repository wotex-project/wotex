defmodule Wotex.Matter.RuntimeRelay.Frame do
  @moduledoc """
  Carries one opaque delivery from a Matter Runtime relay.

  The relay binds each frame to its process, generation and one-use token.
  The `Wotex.Matter.Transport` decoder asks that owner to validate the frame
  against the admitted request before exposing its value and returning native
  credit. The owner rejects fabricated fields and already consumed tokens.

  Inspection exposes only the generation. Payloads and capability tokens stay
  out of diagnostics. Loading this value module starts no relay or transport.
  """

  alias Wotex.Matter.Error

  @derive {Inspect, only: [:generation]}
  @enforce_keys [:pid, :generation, :token, :value]
  defstruct [:pid, :generation, :token, :value]

  @opaque t :: %__MODULE__{
            pid: pid(),
            generation: binary(),
            token: reference(),
            value: {:value, term(), map()} | {:error, Error.t()}
          }
end
