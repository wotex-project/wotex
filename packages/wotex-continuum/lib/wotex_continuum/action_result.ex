defmodule WotexContinuum.ActionResult do
  @moduledoc """
  A portable report about a previously requested Thing Action.

  Status determines which output, failure, and timestamp combinations are
  valid. Successful, failed, and cancelled results must be terminal and
  internally consistent, while accepted or running results remain incomplete.
  The execution scope and evidence references preserve where the report came
  from without making it canonical state.

  This value reports an outcome; it never performs the Action or changes Thing
  state.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{
    Contract,
    Error,
    EvidenceReference,
    ExecutionScope,
    Failure,
    Validation
  }

  @kind "action_result"
  @statuses [:accepted, :running, :succeeded, :failed, :cancelled, :unknown]
  @enforce_keys [:result_id, :intent_id, :status, :context]
  defstruct [
    :result_id,
    :intent_id,
    :status,
    :output,
    :error,
    :started_at,
    :completed_at,
    :context,
    output_present?: false,
    evidence: [],
    extensions: %{}
  ]

  @type status :: :accepted | :running | :succeeded | :failed | :cancelled | :unknown
  @type t :: %__MODULE__{
          result_id: String.t(),
          intent_id: String.t(),
          status: status(),
          output: term(),
          error: Failure.t() | nil,
          started_at: String.t() | nil,
          completed_at: String.t() | nil,
          context: ExecutionScope.t(),
          output_present?: boolean(),
          evidence: [EvidenceReference.t()],
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def from_map(%__MODULE__{output_present?: false, output: nil} = value) do
    value
    |> Validation.struct_input([:error, :started_at, :completed_at])
    |> Map.drop([:output, :output_present?])
    |> from_map()
  end

  def from_map(%__MODULE__{output_present?: true} = value) do
    value
    |> Validation.struct_input([:error, :started_at, :completed_at])
    |> Map.delete(:output_present?)
    |> from_map()
  end

  def from_map(%__MODULE__{}) do
    Error.error(
      :invalid_result_state,
      :validation,
      "/output",
      "Action result fields do not match status"
    )
  end

  def from_map(data) do
    fields = [
      :result_id,
      :intent_id,
      :status,
      :output,
      :error,
      :started_at,
      :completed_at,
      :evidence,
      :context,
      :extensions
    ]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, result_id} <- Validation.required(data, :result_id),
         {:ok, result_id} <- Validation.string(result_id, "/result_id"),
         {:ok, intent_id} <- Validation.required(data, :intent_id),
         {:ok, intent_id} <- Validation.string(intent_id, "/intent_id"),
         {:ok, status} <- Validation.required(data, :status),
         {:ok, status} <- Validation.enum(status, "/status", @statuses),
         {:ok, output, output_present?} <- optional_json(data, :output),
         {:ok, failure} <- optional_nested(data, :error, Failure),
         {:ok, started_at} <- optional_timestamp(data, :started_at),
         {:ok, completed_at} <- optional_timestamp(data, :completed_at),
         :ok <- validate_status(status, output_present?, failure, completed_at),
         :ok <- validate_time_order(started_at, completed_at),
         {:ok, evidence} <-
           Validation.structs(Map.get(data, :evidence, []), "/evidence", EvidenceReference),
         {:ok, context} <- Validation.required(data, :context),
         {:ok, context} <- Validation.nested(context, "/context", ExecutionScope),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), "/extensions") do
      {:ok,
       %__MODULE__{
         result_id: result_id,
         intent_id: intent_id,
         status: status,
         output: output,
         output_present?: output_present?,
         error: failure,
         started_at: started_at,
         completed_at: completed_at,
         evidence: evidence,
         context: context,
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
    |> Map.put("result_id", value.result_id)
    |> Map.put("intent_id", value.intent_id)
    |> Map.put("status", Atom.to_string(value.status))
    |> maybe_put_output(value)
    |> maybe_put("error", value.error && Failure.to_map(value.error))
    |> maybe_put("started_at", value.started_at)
    |> maybe_put("completed_at", value.completed_at)
    |> Map.put("evidence", Enum.map(value.evidence, &EvidenceReference.to_map/1))
    |> Map.put("context", ExecutionScope.to_map(value.context))
    |> Map.put("extensions", value.extensions)
  end

  defp optional_json(data, key) do
    if Map.has_key?(data, key) do
      case Validation.json_value(Map.fetch!(data, key), Error.child("/", Atom.to_string(key))) do
        {:ok, value} -> {:ok, value, true}
        {:error, _} = error -> error
      end
    else
      {:ok, nil, false}
    end
  end

  defp optional_nested(data, key, module) do
    case Map.fetch(data, key) do
      :error ->
        {:ok, nil}

      {:ok, nil} ->
        Error.error(
          :invalid_type,
          :validation,
          Error.child("/", Atom.to_string(key)),
          "expected an object"
        )

      {:ok, value} ->
        Validation.nested(value, Error.child("/", Atom.to_string(key)), module)
    end
  end

  defp optional_timestamp(data, key) do
    case Map.fetch(data, key) do
      :error ->
        {:ok, nil}

      {:ok, nil} ->
        Error.error(
          :invalid_type,
          :validation,
          Error.child("/", Atom.to_string(key)),
          "expected a timestamp"
        )

      {:ok, value} ->
        Validation.timestamp(value, Error.child("/", Atom.to_string(key)))
    end
  end

  defp validate_status(:succeeded, true, nil, completed_at) when is_binary(completed_at), do: :ok

  defp validate_status(:failed, false, %Failure{}, completed_at) when is_binary(completed_at),
    do: :ok

  defp validate_status(:cancelled, false, nil, completed_at) when is_binary(completed_at), do: :ok

  defp validate_status(status, false, nil, nil) when status in [:accepted, :running, :unknown],
    do: :ok

  defp validate_status(status, _, _, _) do
    Error.error(
      :invalid_result_state,
      :validation,
      "/status",
      "result fields do not match the status",
      %{
        status: status
      }
    )
  end

  defp validate_time_order(nil, _), do: :ok
  defp validate_time_order(_, nil), do: :ok

  defp validate_time_order(started_at, completed_at) do
    if Validation.compare_timestamps(started_at, completed_at) in [:lt, :eq],
      do: :ok,
      else:
        Error.error(:invalid_time_order, :validation, "/completed_at", "completion precedes start")
  end

  defp maybe_put_output(map, %__MODULE__{output_present?: true, output: output}),
    do: Map.put(map, "output", output)

  defp maybe_put_output(map, _), do: map

  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
