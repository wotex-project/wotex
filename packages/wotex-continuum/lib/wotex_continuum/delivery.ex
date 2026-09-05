defmodule WotexContinuum.Delivery do
  @moduledoc """
  A data-only snapshot of delivery progress for another continuum value.

  Delivery binds an item to source, destination, attempt, status, timestamps,
  and optional failure. Cross-field validation prevents impossible
  combinations such as acknowledgement without an acknowledgement time.

  The value does not enqueue, transmit, retry, or acknowledge anything.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Error, Failure, Validation}

  @kind "delivery"
  @statuses [:pending, :in_flight, :delivered, :acknowledged, :failed, :unknown]

  @enforce_keys [
    :delivery_id,
    :item_kind,
    :item_id,
    :source,
    :destination,
    :status,
    :attempt,
    :emitted_at
  ]
  defstruct [
    :delivery_id,
    :item_kind,
    :item_id,
    :source,
    :destination,
    :status,
    :attempt,
    :sequence,
    :emitted_at,
    :acknowledged_at,
    :error,
    extensions: %{}
  ]

  @type status :: :pending | :in_flight | :delivered | :acknowledged | :failed | :unknown
  @type t :: %__MODULE__{
          delivery_id: String.t(),
          item_kind: String.t(),
          item_id: String.t(),
          source: String.t(),
          destination: String.t(),
          status: status(),
          attempt: pos_integer(),
          sequence: non_neg_integer() | nil,
          emitted_at: String.t(),
          acknowledged_at: String.t() | nil,
          error: Failure.t() | nil,
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def new(%__MODULE__{} = value),
    do: new(Validation.struct_input(value, [:sequence, :acknowledged_at, :error]))

  def new(data) do
    fields = [
      :delivery_id,
      :item_kind,
      :item_id,
      :source,
      :destination,
      :status,
      :attempt,
      :sequence,
      :emitted_at,
      :acknowledged_at,
      :error,
      :extensions
    ]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, delivery_id} <- Validation.required(data, :delivery_id),
         {:ok, delivery_id} <- Validation.string(delivery_id, ["delivery_id"]),
         {:ok, item_kind} <- Validation.required(data, :item_kind),
         {:ok, item_kind} <- Validation.string(item_kind, ["item_kind"], max: 128),
         :ok <- validate_item_kind(item_kind),
         {:ok, item_id} <- Validation.required(data, :item_id),
         {:ok, item_id} <- Validation.string(item_id, ["item_id"]),
         {:ok, source} <- Validation.required(data, :source),
         {:ok, source} <- Validation.string(source, ["source"]),
         {:ok, destination} <- Validation.required(data, :destination),
         {:ok, destination} <- Validation.string(destination, ["destination"]),
         {:ok, status} <- Validation.required(data, :status),
         {:ok, status} <- Validation.enum(status, ["status"], @statuses),
         {:ok, attempt} <- Validation.required(data, :attempt),
         {:ok, attempt} <- Validation.positive_integer(attempt, ["attempt"]),
         {:ok, sequence} <- optional_sequence(Map.get(data, :sequence)),
         {:ok, emitted_at} <- Validation.required(data, :emitted_at),
         {:ok, emitted_at} <- Validation.timestamp(emitted_at, ["emitted_at"]),
         {:ok, acknowledged_at} <- optional_timestamp(data, :acknowledged_at),
         {:ok, failure} <- optional_failure(data),
         :ok <- validate_status(status, acknowledged_at, failure),
         :ok <- validate_time_order(emitted_at, acknowledged_at),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
      {:ok,
       %__MODULE__{
         delivery_id: delivery_id,
         item_kind: item_kind,
         item_id: item_id,
         source: source,
         destination: destination,
         status: status,
         attempt: attempt,
         sequence: sequence,
         emitted_at: emitted_at,
         acknowledged_at: acknowledged_at,
         error: failure,
         extensions: extensions
       }}
    end
  end

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("delivery_id", value.delivery_id)
    |> Map.put("item_kind", value.item_kind)
    |> Map.put("item_id", value.item_id)
    |> Map.put("source", value.source)
    |> Map.put("destination", value.destination)
    |> Map.put("status", Atom.to_string(value.status))
    |> Map.put("attempt", value.attempt)
    |> maybe_put("sequence", value.sequence)
    |> Map.put("emitted_at", value.emitted_at)
    |> maybe_put("acknowledged_at", value.acknowledged_at)
    |> maybe_put("error", value.error && Failure.to_map(value.error))
    |> Map.put("extensions", value.extensions)
  end

  defp optional_sequence(nil), do: {:ok, nil}
  defp optional_sequence(value), do: Validation.non_negative_integer(value, ["sequence"])

  defp optional_timestamp(data, key) do
    case Map.fetch(data, key) do
      :error -> {:ok, nil}
      {:ok, value} -> Validation.timestamp(value, [Atom.to_string(key)])
    end
  end

  defp optional_failure(data) do
    case Map.fetch(data, :error) do
      :error -> {:ok, nil}
      {:ok, value} -> Validation.nested(value, ["error"], Failure)
    end
  end

  defp validate_status(:acknowledged, acknowledged_at, nil) when is_binary(acknowledged_at), do: :ok
  defp validate_status(:failed, nil, %Failure{}), do: :ok

  defp validate_status(status, nil, nil)
       when status in [:pending, :in_flight, :delivered, :unknown],
       do: :ok

  defp validate_status(status, _, _) do
    Error.error(:invalid_delivery_state, ["status"], "delivery fields do not match the status", %{
      status: status
    })
  end

  defp validate_time_order(_, nil), do: :ok

  defp validate_time_order(emitted_at, acknowledged_at) do
    if Validation.compare_timestamps(emitted_at, acknowledged_at) in [:lt, :eq],
      do: :ok,
      else:
        Error.error(:invalid_time_order, ["acknowledged_at"], "acknowledgement precedes emission")
  end

  defp invalid_item_kind do
    Error.error(:unknown_kind, ["item_kind"], "item kind is not registered")
  end

  defp validate_item_kind(item_kind) do
    if item_kind in WotexContinuum.kinds(), do: :ok, else: invalid_item_kind()
  end

  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
