defmodule Wotex.OPCUA.Error do
  @moduledoc """
  Represents a bounded, credential-free OPC UA failure.

  A `t:t/0` contains a stable code, an optional field, bounded diagnostic
  details, a retry classification, and an effect classification. The effect is
  `:none` when no state-changing service request reached the client and may be
  `:unknown` when a transport or session failure prevents the package from
  determining whether a write or call reached the server.

  `new/3` stores supplied details without redaction or size validation. The
  producer must enforce those constraints. `retryable` is a boolean hint; the
  finite Runtime `class` contract is not yet implemented in this module. Consumers can branch on
  structured fields instead of parsing Python, SDK, or service text. Details
  must not contain credentials, private keys, certificate contents, opaque
  session state, payload values, or unbounded remote output.
  """

  @enforce_keys [:code]
  defstruct [:code, :field, details: %{}, retryable: false, effect: :none]

  @typedoc "A bounded failure; `:unknown` effect means a write may have reached its peer."
  @type t :: %__MODULE__{
          code: atom(),
          field: atom() | nil,
          details: map(),
          retryable: boolean(),
          effect: :none | :unknown
        }

  @doc "Builds a failure from library-owned codes and non-secret details."
  @spec new(atom(), atom() | nil, map()) :: t()
  def new(code, field \\ nil, details \\ %{}),
    do: %__MODULE__{code: code, field: field, details: details}
end
