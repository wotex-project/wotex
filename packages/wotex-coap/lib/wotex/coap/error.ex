defmodule Wotex.CoAP.Error do
  @moduledoc """
  Represents a bounded, credential-free CoAP failure.

  A `t:t/0` contains a stable code, an optional field, bounded details, a retry
  classification, and an effect classification. The effect is `:none` when the
  package can establish that no state-changing request reached the peer and may
  be `:unknown` when a transport or acknowledgment failure prevents that
  conclusion.

  `class` is the finite retry category retained by Wotex Runtime. An uncertain
  mutation is always permanent and non-retryable, including when a consumer
  declares the operation idempotent. This value never schedules a retry.

  `new/3` is the common constructor for message validation, codecs, blockwise
  transfer, Form mapping, connection handling, and Runtime adaptation. It lets
  consumers branch on structured data instead of parsing exceptions or socket
  errors. Diagnostic details must remain bounded and must not retain
  credentials, payloads, opaque socket state, or raw untrusted output.
  """

  @enforce_keys [:code]
  defstruct [:code, :field, class: nil, details: %{}, retryable: false, effect: :none]

  @typedoc "A bounded failure; `:unknown` effect means a write may have reached its peer."
  @type t :: %__MODULE__{
          code: atom(),
          class: :timeout | :unavailable | :rate_limited | :protocol | :permanent | nil,
          field: atom() | nil,
          details: map(),
          retryable: boolean(),
          effect: :none | :unknown
        }

  @doc "Builds a failure from library-owned codes and non-secret details."
  @spec new(atom(), atom() | nil, map()) :: t()
  def new(code, field \\ nil, details \\ %{}),
    do: %__MODULE__{code: code, field: field, details: details, class: classify(code, details)}

  @doc "Retains native effect evidence while preventing retries of uncertain mutations."
  @spec with_effect(t(), :none | :unknown) :: t()
  def with_effect(%__MODULE__{} = error, :unknown),
    do: %{error | effect: :unknown, retryable: false, class: :permanent}

  def with_effect(%__MODULE__{} = error, :none),
    do: %{error | effect: :none, class: classify(error.code, error.details)}

  defp classify(code, _) when code in [:timeout, :deadline_exceeded, :cleanup_timeout],
    do: :timeout

  defp classify(:transport_error, %{reason: :timeout}), do: :timeout

  defp classify(code, _)
       when code in [
              :connection_closed,
              :socket_failed,
              :datagram_failed,
              :transport_error,
              :exchange_unavailable,
              :native_unavailable,
              :context_store_unavailable
            ],
       do: :unavailable

  defp classify(code, _) when code in [:busy, :observation_active, :context_store_locked],
    do: :rate_limited

  defp classify(code, _)
       when code in [
              :invalid_header,
              :invalid_response,
              :invalid_runtime_frame,
              :invalid_transport_return,
              :remote_response,
              :reset,
              :invalid_block,
              :block_out_of_order,
              :invalid_block_payload,
              :incomplete_response,
              :content_format_mismatch,
              :unexpected_content_format,
              :invalid_observation_response,
              :invalid_cancellation_response,
              :representation_changed,
              :overlapping_event_report,
              :unsupported_critical_option,
              :duplicate_option,
              :invalid_option_length,
              :empty_payload_marker,
              :native_protocol_error
            ],
       do: :protocol

  defp classify(code, _)
       when code in [
              :invalid_form,
              :invalid_options,
              :invalid_request,
              :invalid_session,
              :invalid_security,
              :unsupported_security,
              :security_handshake_failed,
              :invalid_transport_context,
              :not_supported,
              :unsupported_profile,
              :invalid_host,
              :invalid_port,
              :invalid_timeout,
              :invalid_ack_timeout,
              :invalid_execution,
              :invalid_observation_options,
              :invalid_subscription,
              :invalid_discovery_request,
              :unsupported_native_backend,
              :invalid_block_size,
              :invalid_datagram_config,
              :invalid_datagram_handle,
              :invalid_datagram,
              :context_store_corrupt,
              :context_store_full,
              :invalid_context_store,
              :fresh_context_required,
              :sequence_exhausted,
              :ssl_not_started
            ],
       do: :permanent

  defp classify(_, _), do: nil
end
