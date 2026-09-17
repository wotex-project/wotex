defmodule Wotex.OPCUA.Error do
  @moduledoc """
  Represents a bounded, credential-free OPC UA failure.

  A `t:t/0` contains a stable code, an optional field, bounded diagnostic
  details, a retry classification, and an effect classification. The effect is
  `:none` when no state-changing service request reached the client and may be
  `:unknown` when a transport or session failure prevents the package from
  determining whether a write or call reached the server.

  `new/3` stores supplied details without redaction or size validation. The
  producer must enforce those constraints. `retryable` is a boolean hint.
  `classify/1` sets the additive Runtime `class`: an unknown effect is
  `:permanent`; otherwise deadlines are `:timeout`, connection and native process
  loss `:unavailable`, admission `:rate_limited`, malformed or mismatched
  responses `:protocol`, and invalid input, route, security or unsupported
  operations `:permanent`. Other codes stay unclassified (`nil`). `retryable`
  becomes true only for the first three classes with no effect. The class does
  not schedule a retry. Consumers can branch on
  structured fields instead of parsing Python, SDK, or service text. Details
  must not contain credentials, private keys, certificate contents, opaque
  session state, payload values, or unbounded remote output.
  """

  @enforce_keys [:code]
  defstruct [:code, :field, :class, details: %{}, retryable: false, effect: :none]

  @typedoc "Runtime failure class, or nil when a failure is unclassified."
  @type class :: :timeout | :unavailable | :rate_limited | :protocol | :permanent | nil

  @typedoc "A bounded failure; `:unknown` effect means a write may have reached its peer."
  @type t :: %__MODULE__{
          code: atom(),
          field: atom() | nil,
          class: class(),
          details: map(),
          retryable: boolean(),
          effect: :none | :unknown
        }

  @classes %{
    timeout: [:deadline_exceeded],
    unavailable: [
      :connection_failed,
      :native_process_terminated,
      :native_startup_failed,
      :native_owner_lost,
      :transport_error,
      :transport_exit
    ],
    rate_limited: [:busy],
    protocol: [
      :response_mismatch,
      :invalid_native_frame,
      :invalid_response,
      :invalid_result,
      :invalid_transport_return,
      :response_limit,
      :sequence_gap,
      :unsupported_remote_reference,
      :invalid_bytestring
    ],
    permanent: [
      :target_mismatch,
      :invalid_form,
      :invalid_form_address,
      :invalid_node_id,
      :invalid_value,
      :invalid_message,
      :invalid_options,
      :invalid_timeout,
      :invalid_transport_context,
      :transport_required,
      :variant_type_required,
      :unsupported_operation,
      :unsupported_type,
      :unsupported_protocol,
      :unsupported_content_type,
      :unsupported_profile,
      :persistent_session_required,
      :not_supported,
      :authentication_failed,
      :certificate_invalid
    ]
  }

  @doc "Builds a failure from library-owned codes and non-secret details."
  @spec new(atom(), atom() | nil, map()) :: t()
  def new(code, field \\ nil, details \\ %{}),
    do: %__MODULE__{code: code, field: field, details: details}

  @doc "Sets the Runtime class and retry hint from the code and effect."
  @spec classify(t()) :: t()
  def classify(%__MODULE__{effect: :unknown} = error),
    do: %{error | class: :permanent, retryable: false}

  def classify(%__MODULE__{code: code} = error) do
    class = Enum.find_value(@classes, fn {class, codes} -> if code in codes, do: class end)
    %{error | class: class, retryable: class in [:timeout, :unavailable, :rate_limited]}
  end
end
