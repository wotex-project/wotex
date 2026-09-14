defmodule Wotex.Matter.EventReport do
  @moduledoc """
  A successful concrete Matter event report with preserved protocol identity.

  Timestamps retain the SDK-reported integer milliseconds and distinguish
  epoch from system time. Unsupported timestamp kinds are rejected rather than
  guessed.
  """

  alias Wotex.Matter.{Address, Error, TLV}

  @enforce_keys [:path, :value, :event_number, :priority, :timestamp, :status]
  defstruct [:path, :value, :event_number, :priority, :timestamp, :status]

  @type timestamp :: %{kind: :epoch | :system, value: non_neg_integer()}
  @type t :: %__MODULE__{
          path: Address.t(),
          value: TLV.element(),
          event_number: non_neg_integer(),
          priority: non_neg_integer(),
          timestamp: timestamp(),
          status: 0
        }

  @doc "Reconstructs and validates a successful event report."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = report), do: new(Map.from_struct(report))

  def new(
        %{
          path: path,
          value: value,
          event_number: event_number,
          priority: priority,
          timestamp: timestamp,
          status: 0
        } = report
      )
      when map_size(report) == 6 do
    with {:ok, path} <- Address.new(path),
         {:ok, value} <- TLV.validate_element(value),
         true <- uint64?(event_number),
         true <- is_integer(priority) and priority in 0..255,
         {:ok, timestamp} <- timestamp(timestamp) do
      {:ok,
       %__MODULE__{
         path: path,
         value: value,
         event_number: event_number,
         priority: priority,
         timestamp: timestamp,
         status: 0
       }}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_event_report)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_event_report)}

  defp timestamp(%{kind: kind, value: value} = timestamp)
       when map_size(timestamp) == 2 and kind in [:epoch, :system] do
    if uint64?(value), do: {:ok, timestamp}, else: :error
  end

  defp timestamp(%{kind: kind} = timestamp)
       when map_size(timestamp) == 2 and is_integer(kind) and kind in 0..0xFFFFFFFF,
       do: {:error, Error.new(:unsupported_timestamp, :timestamp, %{kind: kind})}

  defp timestamp(_), do: :error

  defp uint64?(value), do: is_integer(value) and value in 0..0xFFFFFFFFFFFFFFFF
end
