defmodule Wotex.Matter.Error do
  @moduledoc """
  Carries structured Matter failure information.

  A `t:t/0` contains a stable code, an optional field, diagnostic details, a
  native retry flag, a Runtime retry class, and an effect classification. The
  effect is `:none` when validation or the selected client's submission state
  establishes that no mutation was submitted. It is `:unknown` when a transport
  failure or rejected acknowledgement leaves the effect of a write, invoke,
  commissioning operation or commissioning window uncertain.

  `new/3` is shared by path validation, TLV conversion, Form mapping, Runtime
  transport, and client adapters. Consumers can make policy decisions from
  structured fields rather than parsing SDK or exception text.
  The constructor stores its arguments without sanitizing or sizing them.
  Library call sites and client implementations must enforce the diagnostic
  contract. Details must not contain fabric credentials, private keys, opaque
  controller state, payload values, or unbounded external output.
  """

  @enforce_keys [:code]
  @type class :: :timeout | :unavailable | :rate_limited | :protocol | :permanent | nil

  defstruct [:code, :field, :class, details: %{}, retryable: false, effect: :none]

  @typedoc "A bounded failure; `:unknown` effect means a mutation may have reached its peer."
  @type t :: %__MODULE__{
          code: atom(),
          field: atom() | nil,
          class: class(),
          details: map(),
          retryable: boolean(),
          effect: :none | :unknown
        }

  @doc "Builds a failure from library-owned codes and non-secret details."
  @spec new(atom(), atom() | nil, map()) :: t()
  def new(code, field \\ nil, details \\ %{}) do
    class = classify(code)

    %__MODULE__{
      code: code,
      field: field,
      class: class,
      details: details,
      retryable: class in [:timeout, :unavailable, :rate_limited]
    }
  end

  @doc "Sets the protocol effect and makes unknown-effect failures permanently non-retryable."
  @spec with_effect(t(), :none | :unknown) :: t()
  def with_effect(%__MODULE__{} = error, :unknown),
    do: %{error | effect: :unknown, class: :permanent, retryable: false}

  def with_effect(%__MODULE__{} = error, :none) do
    class = classify(error.code)

    %{
      error
      | effect: :none,
        class: class,
        retryable: class in [:timeout, :unavailable, :rate_limited]
    }
  end

  defp classify(code) when code in [:deadline_exceeded, :timeout], do: :timeout

  defp classify(code)
       when code in [
              :connection_failed,
              :controller_start_failed,
              :exchange_failed,
              :subscription_failed,
              :transport_closed,
              :transport_unavailable
            ],
       do: :unavailable

  defp classify(:busy), do: :rate_limited

  defp classify(code)
       when code in [
              :invalid_attribute_report,
              :invalid_event_report,
              :invalid_frame,
              :invalid_ready,
              :invalid_transport_return,
              :response_limit,
              :response_mismatch
            ],
       do: :protocol

  defp classify(code)
       when code in [
              :controller_configuration_required,
              :endpoint_limit,
              :fabric_mismatch,
              :invalid_commissioning_request,
              :invalid_commissioning_window,
              :invalid_endpoint_catalogue,
              :invalid_form,
              :invalid_form_address,
              :invalid_handle,
              :invalid_message,
              :invalid_options,
              :invalid_path,
              :invalid_path_batch,
              :invalid_request,
              :invalid_subscription,
              :invalid_timeout,
              :invalid_tlv,
              :invalid_transport_context,
              :invalid_value,
              :missing_value,
              :not_supported,
              :not_writable,
              :owner_closed,
              :probe_required,
              :receiver_closed,
              :receiver_overflow,
              :target_mismatch,
              :tlv_limit,
              :transport_required,
              :unsupported_content_type,
              :unsupported_operation,
              :unsupported_profile,
              :unsupported_schema,
              :unsupported_security,
              :unsupported_stream_status,
              :unsupported_timestamp
            ],
       do: :permanent

  defp classify(_), do: nil
end
