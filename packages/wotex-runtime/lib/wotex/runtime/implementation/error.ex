defmodule Wotex.Runtime.Implementation.Error do
  @moduledoc """
  Closed, non-secret failure for implementation admission, lifecycle and codecs.

  Codes determine retry classes. No parser, callback or operating-system text
  is retained. A class describes the failure; it never schedules a retry.
  """

  alias Wotex.Runtime.Implementation.InstanceKey

  @codes ~w(invalid_descriptor limit_exceeded unsupported_schema registration_missing
    duplicate_registration incompatible_api incompatible_binding unsupported_requirement
    unsupported_cell artifact_unverified target_mismatch identity_mismatch deployment_mutable
    trust_unavailable trust_expired trust_revoked rollback_denied permission_denied security_denied
    enforcement_unavailable invalid_configuration invalid_admission_inputs stale_admission
    invalid_transition invalid_instance instance_not_ready instance_draining stale_generation
    startup_failed deadline_exceeded overloaded protocol_fault correlation_failed owner_lost
    session_lost effect_unknown cleanup_unconfirmed state_incompatible invalid_input
    unsupported_format unsupported_value output_limit invalid_metadata schema_mismatch
    codec_unavailable)a
  @phases ~w(construction parse compatibility verification trust policy execution
    startup request delivery drain cleanup admission decode output)a
  @fields ~w(schema id version kind api binding artifact entrypoint support requires
    configuration_schema permissions state limits extensions registrations verification
    trust policy target apis bindings now_ms scope deployment enforcement configuration
    instance_key descriptor registration update valid_until_ms codec_contract security_status
    security_exception metadata value)a

  @type t :: %__MODULE__{
          code: atom(),
          phase: atom(),
          class: atom(),
          field: atom() | nil,
          descriptor_sha256: String.t() | nil,
          instance_key: InstanceKey.t() | nil
        }
  defstruct [:code, :phase, :class, :field, :descriptor_sha256, :instance_key]

  @doc "Builds a closed failure, falling back to a detail-free construction refusal."
  @spec new(term(), term(), term()) :: t()
  def new(code, phase, details) when code in @codes and phase in @phases and is_map(details) do
    if valid_details?(details) do
      struct(__MODULE__, Map.merge(details, %{code: code, phase: phase, class: classify(code)}))
    else
      fallback()
    end
  end

  def new(_, _, _), do: fallback()

  @doc false
  @spec codes() :: nonempty_list(atom())
  def codes, do: @codes

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = error) do
    details = Map.take(error, [:field, :descriptor_sha256, :instance_key])

    map_size(error) == 7 and
      Enum.all?(
        [:code, :phase, :class, :field, :descriptor_sha256, :instance_key],
        &Map.has_key?(error, &1)
      ) and
      error == new(error.code, error.phase, details)
  end

  def valid?(_), do: false

  defp valid_details?(details) do
    map_size(details) <= 3 and
      Enum.all?(Map.keys(details), &(&1 in [:field, :descriptor_sha256, :instance_key])) and
      Map.get(details, :field) in [nil | @fields] and
      valid_digest?(Map.get(details, :descriptor_sha256)) and
      valid_key?(Map.get(details, :instance_key))
  end

  defp valid_digest?(nil), do: true

  defp valid_digest?(digest) when is_binary(digest),
    do: byte_size(digest) == 64 and Regex.match?(~r/\A[0-9a-f]{64}\z/, digest)

  defp valid_digest?(_), do: false
  defp valid_key?(nil), do: true
  defp valid_key?(key), do: InstanceKey.valid?(key)

  defp classify(:deadline_exceeded), do: :timeout

  defp classify(code)
       when code in [:codec_unavailable, :startup_failed, :owner_lost, :session_lost],
       do: :unavailable

  defp classify(:overloaded), do: :rate_limited
  defp classify(code) when code in [:protocol_fault, :correlation_failed], do: :protocol
  defp classify(_), do: :permanent

  defp fallback do
    %__MODULE__{code: :invalid_admission_inputs, phase: :construction, class: :permanent}
  end
end
