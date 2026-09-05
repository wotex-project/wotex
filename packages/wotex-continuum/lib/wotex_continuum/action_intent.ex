defmodule WotexContinuum.ActionIntent do
  @moduledoc """
  A portable, data-only request to invoke a Thing Action.

  The value binds the Action name and input to a Thing, idempotency key,
  execution context, request time, optional requester, and evidence references.
  It is suitable for durable queues and disconnected transfer because all
  authority-relevant context travels with the request.

  Construction validates the envelope; it does not authorize, schedule, dedupe,
  or dispatch the Action. Those decisions remain with the consumer.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, EvidenceReference, ExecutionContext, Validation}

  @kind "action_intent"

  @enforce_keys [
    :intent_id,
    :thing_id,
    :action_name,
    :input,
    :requested_at,
    :idempotency_key,
    :context
  ]
  defstruct [
    :intent_id,
    :thing_id,
    :action_name,
    :input,
    :requested_at,
    :idempotency_key,
    :requested_by,
    :context,
    evidence: [],
    extensions: %{}
  ]

  @type t :: %__MODULE__{
          intent_id: String.t(),
          thing_id: String.t(),
          action_name: String.t(),
          input: term(),
          requested_at: String.t(),
          idempotency_key: String.t(),
          requested_by: String.t() | nil,
          evidence: [EvidenceReference.t()],
          context: ExecutionContext.t(),
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def new(%__MODULE__{} = value), do: new(Validation.struct_input(value, [:requested_by]))

  def new(data) do
    fields = [
      :intent_id,
      :thing_id,
      :action_name,
      :input,
      :requested_at,
      :idempotency_key,
      :requested_by,
      :evidence,
      :context,
      :extensions
    ]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, intent_id} <- Validation.required(data, :intent_id),
         {:ok, intent_id} <- Validation.string(intent_id, ["intent_id"]),
         {:ok, thing_id} <- Validation.required(data, :thing_id),
         {:ok, thing_id} <- Validation.iri(thing_id, ["thing_id"]),
         {:ok, action_name} <- Validation.required(data, :action_name),
         {:ok, action_name} <- Validation.string(action_name, ["action_name"]),
         {:ok, input} <- Validation.required(data, :input),
         {:ok, input} <- Validation.json_value(input, ["input"]),
         {:ok, requested_at} <- Validation.required(data, :requested_at),
         {:ok, requested_at} <- Validation.timestamp(requested_at, ["requested_at"]),
         {:ok, idempotency_key} <- Validation.required(data, :idempotency_key),
         {:ok, idempotency_key} <- Validation.string(idempotency_key, ["idempotency_key"]),
         {:ok, requested_by} <-
           Validation.optional_string(Map.get(data, :requested_by), ["requested_by"], max: 512),
         {:ok, evidence} <-
           Validation.structs(Map.get(data, :evidence, []), ["evidence"], EvidenceReference),
         {:ok, context} <- Validation.required(data, :context),
         {:ok, context} <- Validation.nested(context, ["context"], ExecutionContext),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
      {:ok,
       %__MODULE__{
         intent_id: intent_id,
         thing_id: thing_id,
         action_name: action_name,
         input: input,
         requested_at: requested_at,
         idempotency_key: idempotency_key,
         requested_by: requested_by,
         evidence: evidence,
         context: context,
         extensions: extensions
       }}
    end
  end

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("intent_id", value.intent_id)
    |> Map.put("thing_id", value.thing_id)
    |> Map.put("action_name", value.action_name)
    |> Map.put("input", value.input)
    |> Map.put("requested_at", value.requested_at)
    |> Map.put("idempotency_key", value.idempotency_key)
    |> maybe_put("requested_by", value.requested_by)
    |> Map.put("evidence", Enum.map(value.evidence, &EvidenceReference.to_map/1))
    |> Map.put("context", ExecutionContext.to_map(value.context))
    |> Map.put("extensions", value.extensions)
  end

  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
