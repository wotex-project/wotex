defmodule WotexContinuum.ObservationProposal do
  @moduledoc """
  Proposed Property observation or Event data from continuum execution.

  The proposal binds a Thing affordance value to caller-owned observation time,
  execution context, sequence, quality, evidence, and extensions. It is
  designed for transfer and later admission when a consumer must reconcile
  disconnected observations.

  A proposal is not canonical Thing state and does not emit a W3C Event.
  Consumers validate authority, ordering, and policy before admission.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Error, EvidenceReference, ExecutionContext, Validation}

  @kind "observation_proposal"
  @affordance_types [:property, :event]

  @enforce_keys [
    :proposal_id,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :value,
    :observed_at,
    :context
  ]
  defstruct [
    :proposal_id,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :value,
    :observed_at,
    :sequence,
    :context,
    quality: %{},
    evidence: [],
    extensions: %{}
  ]

  @type affordance_type :: :property | :event
  @type t :: %__MODULE__{
          proposal_id: String.t(),
          thing_id: String.t(),
          affordance_type: affordance_type(),
          affordance_name: String.t(),
          value: term(),
          observed_at: String.t(),
          sequence: non_neg_integer() | nil,
          quality: map(),
          evidence: [EvidenceReference.t()],
          context: ExecutionContext.t(),
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def new(%__MODULE__{} = value), do: new(Validation.struct_input(value, [:sequence]))

  def new(data) do
    fields = [
      :proposal_id,
      :thing_id,
      :affordance_type,
      :affordance_name,
      :value,
      :observed_at,
      :sequence,
      :quality,
      :evidence,
      :context,
      :extensions
    ]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, proposal_id} <- Validation.required(data, :proposal_id),
         {:ok, proposal_id} <- Validation.string(proposal_id, ["proposal_id"]),
         {:ok, thing_id} <- Validation.required(data, :thing_id),
         {:ok, thing_id} <- Validation.iri(thing_id, ["thing_id"]),
         {:ok, affordance_type} <- Validation.required(data, :affordance_type),
         {:ok, affordance_type} <-
           Validation.enum(affordance_type, ["affordance_type"], @affordance_types),
         {:ok, affordance_name} <- Validation.required(data, :affordance_name),
         {:ok, affordance_name} <- Validation.string(affordance_name, ["affordance_name"]),
         {:ok, value} <- Validation.required(data, :value),
         {:ok, value} <- Validation.json_value(value, ["value"]),
         {:ok, observed_at} <- Validation.required(data, :observed_at),
         {:ok, observed_at} <- Validation.timestamp(observed_at, ["observed_at"]),
         {:ok, sequence} <- optional_sequence(Map.get(data, :sequence)),
         {:ok, quality} <- Validation.json_value(Map.get(data, :quality, %{}), ["quality"]),
         :ok <- quality_object(quality),
         {:ok, evidence} <-
           Validation.structs(Map.get(data, :evidence, []), ["evidence"], EvidenceReference),
         {:ok, context} <- Validation.required(data, :context),
         {:ok, context} <- Validation.nested(context, ["context"], ExecutionContext),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
      {:ok,
       %__MODULE__{
         proposal_id: proposal_id,
         thing_id: thing_id,
         affordance_type: affordance_type,
         affordance_name: affordance_name,
         value: value,
         observed_at: observed_at,
         sequence: sequence,
         quality: quality,
         evidence: evidence,
         context: context,
         extensions: extensions
       }}
    end
  end

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("proposal_id", value.proposal_id)
    |> Map.put("thing_id", value.thing_id)
    |> Map.put("affordance_type", Atom.to_string(value.affordance_type))
    |> Map.put("affordance_name", value.affordance_name)
    |> Map.put("value", value.value)
    |> Map.put("observed_at", value.observed_at)
    |> maybe_put("sequence", value.sequence)
    |> Map.put("quality", value.quality)
    |> Map.put("evidence", Enum.map(value.evidence, &EvidenceReference.to_map/1))
    |> Map.put("context", ExecutionContext.to_map(value.context))
    |> Map.put("extensions", value.extensions)
  end

  defp optional_sequence(nil), do: {:ok, nil}
  defp optional_sequence(value), do: Validation.non_negative_integer(value, ["sequence"])

  defp quality_object(value) when is_map(value), do: :ok
  defp quality_object(_), do: Error.error(:invalid_type, ["quality"], "expected an object")

  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
