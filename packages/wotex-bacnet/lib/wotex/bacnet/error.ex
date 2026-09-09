defmodule Wotex.BACnet.Error do
  @moduledoc "Stable, credential-free failures at the BACnet public boundary."

  @classes [:timeout, :unavailable, :rate_limited, :protocol, :permanent]
  @enforce_keys [:code]
  defstruct [:code, :field, class: nil, details: %{}, retryable: false, effect: :none]

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
    do: normalize(%__MODULE__{code: code, field: field, details: details})

  @doc "Sets native effect while preventing unknown-effect failures from authorizing a retry."
  @spec with_effect(t(), :none | :unknown) :: t()
  def with_effect(%__MODULE__{} = error, effect) when effect in [:none, :unknown] do
    class = if effect == error.effect, do: error.class, else: nil
    normalize(%{error | effect: effect, class: class})
  end

  @doc false
  @spec protocol(t()) :: t()
  def protocol(%__MODULE__{} = error), do: normalize(%{error | class: :protocol})

  @doc false
  @spec normalize(t()) :: t()
  def normalize(%__MODULE__{effect: :unknown} = error),
    do: %{error | class: :permanent, retryable: false}

  def normalize(%__MODULE__{class: class} = error) when class in @classes, do: error
  def normalize(%__MODULE__{} = error), do: %{error | class: classification(error.code)}

  defp classification(code) when code in [:deadline_exceeded, :timeout, :lease_expired],
    do: :timeout

  defp classification(code) when code in [:connection_closed, :connection_failed, :transport_exit],
    do: :unavailable

  defp classification(code) when code in [:busy, :discovery_busy], do: :rate_limited

  defp classification(code)
       when code in [
              :response_mismatch,
              :invalid_response,
              :invalid_transport_return,
              :remote_error,
              :remote_reject,
              :remote_abort,
              :invalid_runtime_frame,
              :missing_acknowledgment,
              :invalid_cov_acknowledgment,
              :invalid_cov_notification,
              :conflicting_cov_values,
              :segmented_response_error,
              :conflicting_discovery_response
            ],
       do: :protocol

  defp classification(code) when is_atom(code) do
    if code in [
         :not_supported,
         :missing_value,
         :value_type_required,
         :write_configuration_required,
         :transport_required,
         :writes_disabled,
         :target_mismatch,
         :probe_required,
         :discovery_not_configured,
         :duplicate_property,
         :discovery_limit,
         :segmentation_not_supported
       ] or
         String.starts_with?(Atom.to_string(code), ["invalid_", "unsupported_"]),
       do: :permanent,
       else: nil
  end

  defp classification(_), do: nil
end
