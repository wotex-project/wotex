defmodule Wotex.Binding.HTTP.Error do
  @moduledoc """
  Structured, credential-free failure returned at the HTTP binding boundary.

  `code` supports stable programmatic handling, `phase` identifies the failed
  boundary, `class` carries the retry classification, and `details` contains
  only safe diagnostic context. Client reasons, exceptions, and credential
  material are deliberately omitted.

  Wotex Runtime copies only the atoms `code`, `phase`, and `class` into its own
  error under `details.cause`, so `Wotex.Runtime.Retry.decision/3` can act on a
  classification without any message or detail of this package crossing the
  port boundary.

  | Class | Meaning | Retryable |
  | --- | --- | --- |
  | `:timeout` | HTTP status 408 or a client deadline expiry | yes |
  | `:rate_limited` | HTTP status 429 | yes |
  | `:unavailable` | HTTP status 502, 503, 504, or a failing client call | yes |
  | `:protocol` | codec, representation, handshake, or client-contract failure | no |
  | `:permanent` | configuration, Form, request, or other non-transient failure | no |

  The status-to-class mapping above is complete. Construction and
  validation failures use the non-retryable default `:permanent`; codec,
  representation, and client failures state their class explicitly.
  """

  @type phase ::
          :configuration
          | :form
          | :request
          | :response
          | :codec
          | :client
          | :subscription

  @type class :: :timeout | :unavailable | :rate_limited | :protocol | :permanent | nil

  @type t :: %__MODULE__{
          code: atom(),
          phase: phase(),
          class: class(),
          message: String.t(),
          details: map()
        }

  @classes [:timeout, :unavailable, :rate_limited, :protocol, :permanent]

  @enforce_keys [:code, :phase, :message]
  defexception [:code, :phase, :message, class: :permanent, details: %{}]

  @doc false
  @spec new(atom(), phase(), String.t(), map(), class()) :: t()
  def new(code, phase, message, details \\ %{}, class \\ :permanent)
      when is_atom(code) and is_atom(phase) and is_binary(message) and is_map(details) and
             class in @classes do
    %__MODULE__{code: code, phase: phase, class: class, message: message, details: details}
  end

  @doc "Returns the retry classification of a binding failure."
  @spec class(t()) :: class()
  def class(%__MODULE__{class: class}), do: class
end
