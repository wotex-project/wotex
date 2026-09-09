defmodule WotexContinuum.ExitReceipt do
  @moduledoc """
  Evidence that an export or removal operation was attempted.

  The receipt records operation, status, request and completion times, exported
  artifacts, residual descriptions, failures, and evidence. Its cross-field
  rules distinguish completed, partial, failed, and in-progress outcomes
  without claiming more than the consumer observed.

  Constructing a receipt performs no export or removal.

  Validation relates operation, status, completion time, residuals, artifacts,
  and failure details. In particular, a completed removal cannot report
  residual state, whereas a partial outcome must. The versioned map returned by
  `to_map/1` is evidence supplied by the caller, not proof of deletion.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Error, EvidenceReference, Failure, Validation}

  @kind "exit_receipt"
  @operations [:export, :remove]
  @statuses [:requested, :running, :completed, :failed, :partial]

  @enforce_keys [:receipt_id, :subject_id, :operation, :status, :requested_at]
  defstruct [
    :receipt_id,
    :subject_id,
    :operation,
    :status,
    :requested_at,
    :completed_at,
    :error,
    artifacts: [],
    residuals: [],
    extensions: %{}
  ]

  @type operation :: :export | :remove
  @type status :: :requested | :running | :completed | :failed | :partial
  @type t :: %__MODULE__{
          receipt_id: String.t(),
          subject_id: String.t(),
          operation: operation(),
          status: status(),
          requested_at: String.t(),
          completed_at: String.t() | nil,
          artifacts: [EvidenceReference.t()],
          residuals: [String.t()],
          error: Failure.t() | nil,
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def from_map(%__MODULE__{} = value),
    do: from_map(Validation.struct_input(value, [:completed_at, :error]))

  def from_map(data) do
    fields = [
      :receipt_id,
      :subject_id,
      :operation,
      :status,
      :requested_at,
      :completed_at,
      :artifacts,
      :residuals,
      :error,
      :extensions
    ]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, receipt_id} <- Validation.required(data, :receipt_id),
         {:ok, receipt_id} <- Validation.string(receipt_id, "/receipt_id"),
         {:ok, subject_id} <- Validation.required(data, :subject_id),
         {:ok, subject_id} <- Validation.string(subject_id, "/subject_id"),
         {:ok, operation} <- Validation.required(data, :operation),
         {:ok, operation} <- Validation.enum(operation, "/operation", @operations),
         {:ok, status} <- Validation.required(data, :status),
         {:ok, status} <- Validation.enum(status, "/status", @statuses),
         {:ok, requested_at} <- Validation.required(data, :requested_at),
         {:ok, requested_at} <- Validation.timestamp(requested_at, "/requested_at"),
         {:ok, completed_at} <- optional_timestamp(data),
         {:ok, artifacts} <-
           Validation.structs(Map.get(data, :artifacts, []), "/artifacts", EvidenceReference),
         {:ok, residuals} <- Validation.string_list(Map.get(data, :residuals, []), "/residuals"),
         {:ok, failure} <- optional_failure(data),
         :ok <- validate_status(operation, status, completed_at, residuals, failure),
         :ok <- validate_time_order(requested_at, completed_at),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), "/extensions") do
      {:ok,
       %__MODULE__{
         receipt_id: receipt_id,
         subject_id: subject_id,
         operation: operation,
         status: status,
         requested_at: requested_at,
         completed_at: completed_at,
         artifacts: artifacts,
         residuals: residuals,
         error: failure,
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
    |> Map.put("receipt_id", value.receipt_id)
    |> Map.put("subject_id", value.subject_id)
    |> Map.put("operation", Atom.to_string(value.operation))
    |> Map.put("status", Atom.to_string(value.status))
    |> Map.put("requested_at", value.requested_at)
    |> maybe_put("completed_at", value.completed_at)
    |> Map.put("artifacts", Enum.map(value.artifacts, &EvidenceReference.to_map/1))
    |> Map.put("residuals", value.residuals)
    |> maybe_put("error", value.error && Failure.to_map(value.error))
    |> Map.put("extensions", value.extensions)
  end

  defp optional_timestamp(data) do
    case Map.fetch(data, :completed_at) do
      :error -> {:ok, nil}
      {:ok, value} -> Validation.timestamp(value, "/completed_at")
    end
  end

  defp optional_failure(data) do
    case Map.fetch(data, :error) do
      :error -> {:ok, nil}
      {:ok, value} -> Validation.nested(value, "/error", Failure)
    end
  end

  defp validate_status(_, status, nil, [], nil) when status in [:requested, :running],
    do: :ok

  defp validate_status(:remove, :completed, completed_at, [], nil) when is_binary(completed_at),
    do: :ok

  defp validate_status(:export, :completed, completed_at, _, nil)
       when is_binary(completed_at), do: :ok

  defp validate_status(_, :partial, completed_at, residuals, nil)
       when is_binary(completed_at) and residuals != [],
       do: :ok

  defp validate_status(_, :failed, completed_at, _, %Failure{})
       when is_binary(completed_at),
       do: :ok

  defp validate_status(_, status, _, _, _) do
    Error.error(
      :invalid_exit_state,
      :validation,
      "/status",
      "exit fields do not match the status",
      %{
        status: status
      }
    )
  end

  defp validate_time_order(_, nil), do: :ok

  defp validate_time_order(requested_at, completed_at) do
    if Validation.compare_timestamps(requested_at, completed_at) in [:lt, :eq],
      do: :ok,
      else:
        Error.error(
          :invalid_time_order,
          :validation,
          "/completed_at",
          "completion precedes request"
        )
  end

  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
