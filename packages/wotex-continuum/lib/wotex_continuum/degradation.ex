defmodule WotexContinuum.Degradation do
  @moduledoc """
  Typed report of reduced or unavailable capability.
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

  @impl true
  def kind, do: @kind

  @impl true
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
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
         {:ok, degradation_id} <- Validation.string(degradation_id, ["degradation_id"]),
         {:ok, subject_id} <- Validation.required(data, :subject_id),
         {:ok, subject_id} <- Validation.string(subject_id, ["subject_id"]),
         {:ok, level} <- Validation.required(data, :level),
         {:ok, level} <- Validation.enum(level, ["level"], @levels),
         {:ok, capabilities} <- Validation.required(data, :capabilities),
         {:ok, capabilities} <- Validation.string_list(capabilities, ["capabilities"]),
         {:ok, reason_codes} <- Validation.required(data, :reason_codes),
         {:ok, reason_codes} <- Validation.string_list(reason_codes, ["reason_codes"]),
         :ok <- validate_level(level, capabilities, reason_codes),
         {:ok, since} <- Validation.required(data, :since),
         {:ok, since} <- Validation.timestamp(since, ["since"]),
         {:ok, recoverable} <- Validation.required(data, :recoverable),
         {:ok, recoverable} <- Validation.boolean(recoverable, ["recoverable"]),
         {:ok, evidence} <-
           Validation.structs(Map.get(data, :evidence, []), ["evidence"], EvidenceReference),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
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

  @impl true
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

  defp validate_level(_level, _capabilities, _reason_codes) do
    Error.error(
      :invalid_degradation_state,
      ["level"],
      "degradation details do not match the level"
    )
  end
end
