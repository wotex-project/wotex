defmodule Wotex.Thread.Error do
  @moduledoc """
  Represents a bounded, credential-free Thread failure.

  A `t:t/0` contains a stable code, an optional field, bounded diagnostic
  details, a retry classification, and an effect classification. The daemon
  profile is read-only. Native SDK mutations report `effect: :unknown` when
  completion is lost after submission; this does not establish a remote effect.

  `new/3` stores library-supplied fields without sanitizing arbitrary input.
  It is shared by Operational Dataset parsing, request validation, Form
  mapping, Runtime transport, and client adapters. Consumers can branch on
  structured fields instead of parsing socket or daemon text. Diagnostic
  details must not contain Thread network keys, raw dataset bytes, credentials,
  opaque socket state, or unbounded external output. A retry classification is
  information for consumer policy, not permission to retry automatically.
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
