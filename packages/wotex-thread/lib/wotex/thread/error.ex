defmodule Wotex.Thread.Error do
  @moduledoc """
  Represents a bounded, credential-free Thread failure.

  A `t:t/0` contains a stable code, an optional field, bounded diagnostic
  details, a Runtime failure class, a retry classification, and an effect
  classification. The daemon profile is read-only. Native SDK mutations report
  `effect: :unknown` when completion is lost after submission; uncertain effect
  is always permanent and non-retryable.

  `new/3` stores library-supplied fields without sanitizing arbitrary input.
  It is shared by Operational Dataset parsing, request validation, Form
  mapping, Runtime transport, and client adapters. Consumers can branch on
  structured fields instead of parsing socket or daemon text. Diagnostic
  details must not contain Thread network keys, raw dataset bytes, credentials,
  opaque socket state, or unbounded external output. A retry classification is
  information for consumer policy, not permission to retry automatically.
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

  defp classify_code(code)
       when code in [
              :timeout,
              :deadline_exceeded,
              :cleanup_timeout,
              :formation_timeout,
              :management_timeout,
              :commissioner_timeout,
              :joiner_timeout
            ],
       do: :timeout

  defp classify_code(code)
       when code in [
              :connection_failed,
              :connect_failed,
              :connection_closed,
              :transport_closed,
              :transport_error,
              :transport_exception,
              :transport_exit,
              :transport_throw,
              :transport_unavailable,
              :storage_unavailable
            ],
       do: :unavailable

  defp classify_code(code) when code in [:busy, :receiver_overflow], do: :rate_limited

  defp classify_code(code)
       when code in [
              :invalid_response,
              :remote_error,
              :response_mismatch,
              :invalid_transport_return,
              :response_limit
            ],
       do: :protocol

  defp classify_code(code)
       when code in [
              :cancelled,
              :commissioner_rejected,
              :creation_not_allowed,
              :dataset_exists,
              :dataset_not_found,
              :dataset_required,
              :duplicate_tlv,
              :invalid_callback,
              :invalid_dataset,
              :invalid_dataset_kind,
              :invalid_form,
              :invalid_form_address,
              :invalid_handle,
              :invalid_joiner_admission,
              :invalid_joiner_config,
              :invalid_joiner_identity,
              :invalid_message,
              :invalid_options,
              :invalid_request,
              :invalid_session,
              :invalid_state,
              :invalid_subscription,
              :invalid_timeout,
              :invalid_tlv,
              :invalid_transport_context,
              :invalid_value,
              :not_owned,
              :not_supported,
              :owner_down,
              :probe_required,
              :subscription_not_found,
              :target_mismatch,
              :transport_required,
              :truncated_dataset,
              :unsupported_content_type,
              :unsupported_operation,
              :unsupported_profile,
              :unsupported_security,
              :wrong_owner,
              :already_open,
              :interface_in_use
            ],
       do: :permanent

  defp classify_code(_), do: nil
end
