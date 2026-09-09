defmodule Wotex.Modbus.Error do
  @moduledoc "Stable, credential-free failures at the Modbus public boundary."

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

  @doc "Classifies an effect conservatively; an uncertain mutation can never authorize retry."
  @spec with_effect(t(), :none | :unknown) :: t()
  def with_effect(%__MODULE__{} = error, :unknown),
    do: %{error | effect: :unknown, retryable: false, class: :permanent}

  def with_effect(%__MODULE__{} = error, :none),
    do: %{error | effect: :none, class: classify(error.code, error.details)}

  defp classify(code, _) when code in [:deadline_exceeded, :cleanup_timeout], do: :timeout
  defp classify(:transport_error, %{reason: :timeout}), do: :timeout

  defp classify(code, _) when code in [:connect_failed, :connection_closed, :transport_error],
    do: :unavailable

  defp classify(:busy, _), do: :rate_limited

  defp classify(code, _)
       when code in [
              :invalid_frame,
              :invalid_mbap,
              :invalid_response,
              :invalid_padding,
              :response_mismatch,
              :remote_exception
            ],
       do: :protocol

  defp classify(code, _)
       when code in [
              :address_overflow,
              :invalid_address,
              :invalid_address_base,
              :invalid_command,
              :invalid_deadline,
              :invalid_form,
              :invalid_health_probe,
              :invalid_host,
              :invalid_href,
              :invalid_mapping,
              :invalid_message,
              :invalid_options,
              :invalid_order,
              :invalid_quantity,
              :invalid_request,
              :invalid_session,
              :invalid_timeout,
              :invalid_transport_context,
              :invalid_unit,
              :invalid_value,
              :missing_function,
              :not_supported,
              :operation_mismatch,
              :quantity_mismatch,
              :unsupported_conversion,
              :unsupported_function,
              :unsupported_operation,
              :unsupported_security,
              :unsupported_type,
              :unsupported_profile,
              :unsupported_content_type
            ],
       do: :permanent

  defp classify(_, _), do: nil
end
