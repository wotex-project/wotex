defmodule WotexContinuum.Degradation do
  @moduledoc """
  A typed report that a subject is reduced or unavailable.

  The report names affected capabilities, reason codes, onset time,
  recoverability, optional evidence, and the declared degradation level. It can
  cross disconnected boundaries without requiring a shared process or log.

  The value reports consumer-supplied state; it does not monitor health or
  change runtime behavior itself.

  Cross-field validation prevents a `:none` report from carrying affected
  capabilities or reasons and requires reduced or unavailable reports to name
  both. `to_map/1` preserves the admitted evidence and extensions for transport
  without promoting the report to a health authority.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Error, EvidenceReference, Validation}

  @kind "degradation"
  @levels [:none, :reduced, :unavailable]

  @enforce_keys [
    :degradation_id,
    :subject_id,
    :level,
    :capabilities,
    :reason_codes,
    :since,
    :recoverable
  ]
  defstruct [
    :degradation_id,
    :subject_id,
    :level,
    :capabilities,
    :reason_codes,
    :since,
    :recoverable,
    evidence: [],
    extensions: %{}
  ]

  @type level :: :none | :reduced | :unavailable
  @type t :: %__MODULE__{
          degradation_id: String.t(),
          subject_id: String.t(),
          level: level(),
          capabilities: [String.t()],
          reason_codes: [String.t()],
          since: String.t(),
          recoverable: boolean(),
          evidence: [EvidenceReference.t()],
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def from_map(%__MODULE__{} = value), do: from_map(Map.from_struct(value))

  def from_map(data) do
    fields = [
      :degradation_id,
      :subject_id,
      :level,
      :capabilities,
      :reason_codes,
      :since,
      :recoverable,
      :evidence,
      :extensions
    ]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, degradation_id} <- Validation.required(data, :degradation_id),
         {:ok, degradation_id} <- Validation.string(degradation_id, "/degradation_id"),
         {:ok, subject_id} <- Validation.required(data, :subject_id),
         {:ok, subject_id} <- Validation.string(subject_id, "/subject_id"),
         {:ok, level} <- Validation.required(data, :level),
         {:ok, level} <- Validation.enum(level, "/level", @levels),
         {:ok, capabilities} <- Validation.required(data, :capabilities),
         {:ok, capabilities} <- Validation.string_list(capabilities, "/capabilities"),
         {:ok, reason_codes} <- Validation.required(data, :reason_codes),
         {:ok, reason_codes} <- Validation.string_list(reason_codes, "/reason_codes"),
         :ok <- validate_level(level, capabilities, reason_codes),
         {:ok, since} <- Validation.required(data, :since),
         {:ok, since} <- Validation.timestamp(since, "/since"),
         {:ok, recoverable} <- Validation.required(data, :recoverable),
         {:ok, recoverable} <- Validation.boolean(recoverable, "/recoverable"),
         {:ok, evidence} <-
           Validation.structs(Map.get(data, :evidence, []), "/evidence", EvidenceReference),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), "/extensions") do
      {:ok,
       %__MODULE__{
         degradation_id: degradation_id,
         subject_id: subject_id,
         level: level,
         capabilities: capabilities,
         reason_codes: reason_codes,
         since: since,
         recoverable: recoverable,
         evidence: evidence,
         extensions: extensions
       }}
    end
  end

  @doc "Alias of `from_map/1` retained for the 0.1 constructor API."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(data), do: from_map(data)

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("degradation_id", value.degradation_id)
    |> Map.put("subject_id", value.subject_id)
    |> Map.put("level", Atom.to_string(value.level))
    |> Map.put("capabilities", value.capabilities)
    |> Map.put("reason_codes", value.reason_codes)
    |> Map.put("since", value.since)
    |> Map.put("recoverable", value.recoverable)
    |> Map.put("evidence", Enum.map(value.evidence, &EvidenceReference.to_map/1))
    |> Map.put("extensions", value.extensions)
  end

  defp validate_level(:none, [], []), do: :ok

  defp validate_level(level, capabilities, reason_codes)
       when level in [:reduced, :unavailable] and capabilities != [] and reason_codes != [],
       do: :ok

  defp validate_level(_, _, _) do
    Error.error(
      :invalid_degradation_state,
      :validation,
      "/level",
      "degradation details do not match the level"
    )
  end
end
