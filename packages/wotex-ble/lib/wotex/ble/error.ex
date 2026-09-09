defmodule Wotex.BLE.Error do
  @moduledoc """
  Carries structured BLE failure information and Runtime classification.

  Each `t:t/0` contains a stable code, an optional field, diagnostic details, a
  retry classification, and an effect classification. The effect remains
  `:none` when no write reached the client and may be `:unknown` when transport
  failure prevents the package from determining whether an acknowledged write
  reached BlueZ or the peer.

  `new/3` is used by address validation, UUID and value codecs, Form mapping,
  Runtime transport, and client adapters. Consumers can branch on structured
  fields instead of parsing exception or command output. Details are diagnostic
  data only; they must not contain credentials, opaque handles, or unbounded
  operating-system responses. The constructor stores details without sanitizing
  or sizing them; library call sites and client implementations enforce those
  restrictions. Unknown mutation effect forces permanent classification and
  disables retry.
  """

  @enforce_keys [:code]
  defstruct [:code, :field, :class, details: %{}, retryable: false, effect: :none]

  @typedoc "A bounded failure; `:unknown` effect means a write may have reached its peer."
  @type t :: %__MODULE__{
          code: atom(),
          field: atom() | nil,
          class: :timeout | :unavailable | :rate_limited | :protocol | :permanent | nil,
          details: map(),
          retryable: boolean(),
          effect: :none | :unknown
        }

  @doc "Builds a failure from library-owned codes and non-secret details."
  @spec new(atom(), atom() | nil, map()) :: t()
  def new(code, field \\ nil, details \\ %{}),
    do: %__MODULE__{code: code, field: field, details: details, class: classify_code(code)}

  @doc false
  @spec unknown_effect(t()) :: t()
  def unknown_effect(%__MODULE__{} = error),
    do: %{error | effect: :unknown, class: :permanent, retryable: false}

  @doc false
  @spec classify(t()) :: t()
  def classify(%__MODULE__{effect: :unknown} = error), do: unknown_effect(error)

  def classify(%__MODULE__{} = error),
    do: %{error | class: classify_code(error.code), retryable: false}

  defp classify_code(code) when code in [:timeout, :deadline_exceeded], do: :timeout

  defp classify_code(code)
       when code in [
              :disconnected,
              :connection_failed,
              :transport_unavailable,
              :owner_changed,
              :peer_not_found,
              :services_unresolved,
              :transport_error,
              :transport_exception,
              :transport_exit,
              :transport_throw
            ],
       do: :unavailable

  defp classify_code(:busy), do: :rate_limited

  defp classify_code(code)
       when code in [
              :invalid_response,
              :response_mismatch,
              :invalid_transport_return,
              :response_limit,
              :snapshot_unstable,
              :peer_changed
            ],
       do: :protocol

  defp classify_code(code)
       when code in [
              :address_mismatch,
              :target_mismatch,
              :invalid_address,
              :invalid_challenge,
              :invalid_characteristic,
              :invalid_form,
              :invalid_form_address,
              :invalid_generation,
              :invalid_handle,
              :invalid_message,
              :invalid_object_path,
              :invalid_options,
              :incompatible_backend,
              :invalid_peer,
              :invalid_request,
              :invalid_session,
              :invalid_subscription,
              :invalid_timeout,
              :invalid_transport_context,
              :invalid_uuid,
              :invalid_value,
              :not_supported,
              :pairing_rejected,
              :probe_required,
              :transport_required,
              :unsupported_operation,
              :unsupported_procedure_selection,
              :unsupported_profile,
              :unsupported_content_type,
              :unsupported_security,
              :invalid_selector,
              :not_permitted,
              :not_authorized,
              :invalid_value_length,
              :invalid_offset,
              :improperly_configured,
              :ambiguous_peer,
              :ambiguous_characteristic,
              :invalid_cursor,
              :stale_discovery,
              :already_subscribed
            ],
       do: :permanent

  defp classify_code(_), do: nil
end
