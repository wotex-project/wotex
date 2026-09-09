defmodule Wotex.CoAP.Error do
  @moduledoc """
  Represents a bounded, credential-free CoAP failure.

  A `t:t/0` contains a stable code, an optional field, bounded details, a retry
  classification, and an effect classification. The effect is `:none` when the
  package can establish that no state-changing request reached the peer and may
  be `:unknown` when a transport or acknowledgment failure prevents that
  conclusion.

  `new/3` is the common constructor for message validation, codecs, blockwise
  transfer, Form mapping, connection handling, and Runtime adaptation. It lets
  consumers branch on structured data instead of parsing exceptions or socket
  errors. Diagnostic details must remain bounded and must not retain
  credentials, payloads, opaque socket state, or raw untrusted output.
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
