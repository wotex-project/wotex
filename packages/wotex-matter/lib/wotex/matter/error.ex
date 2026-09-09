defmodule Wotex.Matter.Error do
  @moduledoc """
  Carries structured Matter failure information.

  A `t:t/0` contains a stable code, an optional field, diagnostic
  details, a retry classification, and an effect classification. The effect is
  `:none` when no state-changing interaction reached the client and may be
  `:unknown` when a transport failure prevents the package from determining
  whether a write or invoke reached its target.

  `new/3` is shared by path validation, TLV conversion, Form mapping, Runtime
  transport, and client adapters. Consumers can make policy decisions from
  structured fields rather than parsing Python, SDK, or exception text.
  The constructor stores its arguments without sanitizing or sizing them.
  Library call sites and client implementations must enforce the diagnostic
  contract. Details must not contain fabric credentials, private keys, opaque
  controller state, payload values, or unbounded external output.
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
