defmodule WotexLabWorkbench.ThingReadings do
  @moduledoc "Bounded Property receipts and stream state owned by one Workbench view."

  @doc "Retains one receipt for the exact Thing and Property."
  @spec put(map(), map()) :: map()
  def put(readings, reading),
    do: Map.put(readings, reading.thing <> "/" <> reading.property, reading)

  @doc "Fetches one exact Property, including a retained manual-read presentation."
  @spec get(map(), String.t(), String.t()) :: map() | nil
  def get(readings, thing, property) when is_binary(property) do
    case Map.get(readings, thing <> "/" <> property, Map.get(readings, thing)) do
      %{thing: ^thing, property: ^property} = reading -> reading
      _ -> nil
    end
  end

  def get(_, _, _), do: nil

  @doc "Marks retained stream values paused without retaining a worker or restarting one."
  @spec pause(map()) :: map()
  def pause(readings),
    do:
      Map.new(readings, fn {key, reading} ->
        {key,
         if(Map.get(reading, :state) in [:waiting, :live, :stale],
           do: Map.put(reading, :state, :paused),
           else: reading
         )}
      end)

  @doc "Updates presentation freshness using the host's explicit monotonic millisecond."
  @spec expire(map(), integer()) :: map()
  def expire(readings, now),
    do:
      Map.new(readings, fn {key, reading} ->
        {key,
         if(Map.get(reading, :state) == :live and now - reading.received_ms > 15_000,
           do: Map.put(reading, :state, :stale),
           else: reading
         )}
      end)

  @doc "Returns a compact receipt time; the inspector retains the full timestamp."
  @spec time(map()) :: String.t()
  def time(reading) do
    case DateTime.from_iso8601(Map.get(reading, :read_at, "")) do
      {:ok, date, _} -> Calendar.strftime(date, "%H:%M:%S")
      _ -> ""
    end
  end

  @doc "Returns an explicit observed, cached or unavailable presentation state."
  @spec status(map()) :: String.t()
  def status(reading) do
    case Map.get(reading, :state, :read) do
      :waiting -> "Waiting"
      :live -> "Live"
      :stale -> "Stale"
      :paused -> "Paused"
      :disconnected -> "Disconnected"
      :error -> "Error"
      _ -> "Read"
    end
  end
end
