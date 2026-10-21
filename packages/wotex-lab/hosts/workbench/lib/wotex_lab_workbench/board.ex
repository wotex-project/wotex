defmodule WotexLabWorkbench.Board do
  @moduledoc """
  Bounded session-owned metric pins and saved canvas geometry.

  Pin definitions come from the fixed metric catalogue and executed room-history
  results. Browser layout input supplies geometry only, never chart values,
  query expressions, source scope or command authority. Restoring a board reads
  its cached results without executing another query.
  """

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Chart
  alias WotexLabWorkbench.Observability.Panels

  @max_pins 16

  @doc "Returns an empty session presentation value."
  @spec empty() :: map()
  def empty, do: %{pins: [], layout: nil, revision: 0}

  @doc "Applies one closed server-owned pin operation or validated browser layout."
  @spec change(map(), term()) :: {:ok, map()} | {:error, Error.t()}
  def change(board, {:pin, history}) do
    with {:ok, metric, result} <- one_result(history),
         true <- measured?(result),
         id = pin_id(metric.id, history.range),
         previous = Enum.find(board.pins, &(&1.id == id)),
         true <- previous != nil or length(board.pins) < @max_pins do
      pin = %{
        id: id,
        metric: metric.id,
        range: history.range,
        title: if(previous, do: previous.title, else: metric.title),
        paused: false,
        result: result,
        window: Map.take(history, [:start_ms, :end_ms, :step_ms]),
        checked_at: Map.get(history, :queried_at, history.end_ms),
        error: nil
      }

      pins = if previous, do: replace(board.pins, pin), else: [pin | board.pins]
      {:ok, %{board | pins: pins}}
    else
      _ -> invalid(:unavailable_pin, "Pin requires measured room history and an available slot")
    end
  end

  def change(board, {:refresh, histories}) when is_list(histories) and length(histories) <= 3 do
    Enum.reduce_while(histories, {:ok, board}, fn history, {:ok, current} ->
      case refresh(current, history) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  def change(board, {:remove, id}) do
    with {:ok, _} <- fetch(board, id) do
      {:ok, %{board | pins: Enum.reject(board.pins, &(&1.id == id))}}
    end
  end

  def change(board, {:pause, id, paused}) when is_boolean(paused) do
    with {:ok, pin} <- fetch(board, id),
         do: {:ok, %{board | pins: replace(board.pins, %{pin | paused: paused})}}
  end

  def change(board, {:rename, id, title})
      when is_binary(title) and byte_size(title) in 1..128 do
    with true <- String.valid?(title) and String.trim(title) != "",
         {:ok, pin} <- fetch(board, id) do
      {:ok, %{board | pins: replace(board.pins, %{pin | title: String.trim(title)})}}
    else
      _ -> invalid(:invalid_pin, "Use a title of 1–128 UTF-8 bytes")
    end
  end

  def change(board, {:layout, layout, allowed_ids}) when is_list(allowed_ids) do
    ids = allowed_ids ++ Enum.map(board.pins, & &1.id)

    if layout?(layout, ids),
      do: {:ok, %{board | layout: layout, revision: board.revision + 1}},
      else: invalid(:invalid_layout, "Layout must contain only current canvas geometry")
  end

  def change(_, _), do: invalid(:invalid_board_operation, "Board operation is not admitted")

  @doc "Finds only a pin already owned by this board."
  @spec fetch(map(), term()) :: {:ok, map()} | {:error, Error.t()}
  def fetch(board, id) do
    case Enum.find(board.pins, &(&1.id == id)) do
      nil -> invalid(:unknown_pin, "Pin is not in this session")
      pin -> {:ok, pin}
    end
  end

  @doc "Tests whether an executed panel contains a measured value."
  @spec measured?(term()) :: boolean()
  def measured?(%{status: :available, chart: %Chart{} = chart}) do
    case Chart.new(Map.to_list(Map.from_struct(chart))) do
      {:ok, admitted} ->
        Enum.any?(admitted.series, fn s -> Enum.any?(s.points, &is_number(elem(&1, 1))) end)

      _ ->
        false
    end
  end

  def measured?(_), do: false

  @doc "Discards cached observations after the owning room dies."
  @spec clear_results(map()) :: map()
  def clear_results(board) do
    %{board | pins: Enum.map(board.pins, &%{&1 | result: nil, paused: true, error: "Room ended"})}
  end

  @doc "Adds bounded metric presentations and saved geometry to a Thing graph."
  @spec decorate(map(), map(), MapSet.t()) :: map()
  def decorate(props, board, active \\ MapSet.new()) do
    positions = Map.new((board.layout && board.layout["positions"]) || [], &{&1["id"], &1})

    nodes =
      Enum.map(props["nodes"], fn node ->
        Map.merge(node, Map.take(Map.get(positions, node["id"], %{}), ["x", "y"]))
      end)

    pins =
      board.pins
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {pin, index} -> pin_payload(pin, index, positions, active) end)

    Map.merge(props, %{
      "nodes" => nodes,
      "pins" => pins,
      "selection" =>
        if(props["selection"] in Enum.map(nodes ++ pins, & &1["id"]),
          do: props["selection"],
          else: ""
        ),
      "view" => if(board.layout, do: [board.layout["viewport"]], else: []),
      "layout_revision" => Integer.to_string(board.revision)
    })
  end

  defp pin_payload(pin, index, positions, active) do
    position = Map.get(positions, pin.id, %{})
    chart = pin.result && pin.result.chart

    %{
      "id" => pin.id,
      "title" => pin.title,
      "metric" => pin.metric,
      "source" => "Room history",
      "range" => pin.range,
      "unit" => if(pin.result, do: pin.result.display_unit, else: ""),
      "aggregation" => if(pin.result, do: pin.result.aggregation, else: ""),
      "state" => pin_state(pin, active),
      "auto_refresh" => not pin.paused and MapSet.member?(active, pin.id),
      "end_ms" => pin.window.end_ms,
      "series" => if(chart, do: Enum.map(chart.series, &series/1), else: []),
      "x" => Map.get(position, "x", 1080),
      "y" => Map.get(position, "y", 80 + index * 280),
      "width" => Map.get(position, "width", 360),
      "height" => Map.get(position, "height", 280)
    }
  end

  defp pin_state(%{error: error, result: nil}, _) when is_binary(error), do: error
  defp pin_state(%{error: error}, _) when is_binary(error), do: "Cached · " <> error
  defp pin_state(%{paused: true}, _), do: "Paused"
  defp pin_state(pin, active), do: if(MapSet.member?(active, pin.id), do: "Auto", else: "Paused")

  defp series(series),
    do: %{"name" => series.name, "points" => Enum.map(series.points, fn {x, y} -> [x, y] end)}

  defp refresh(board, %{range: range, panels: results} = history) when is_list(results) do
    with true <- history?(history),
         true <-
           length(results) <= @max_pins and
             Enum.all?(results, &match?({:ok, _, _}, one_result(%{history | panels: [&1]}))) do
      pins =
        Enum.map(board.pins, fn pin ->
          result = Enum.find(results, &(&1.id == pin.metric))

          cond do
            pin.range != range or result == nil ->
              pin

            measured?(result) ->
              %{
                pin
                | result: result,
                  window: Map.take(history, [:start_ms, :end_ms, :step_ms]),
                  checked_at: Map.get(history, :queried_at, history.end_ms),
                  error: nil
              }

            true ->
              %{
                pin
                | checked_at: Map.get(history, :queried_at, history.end_ms),
                  error: "Refresh unavailable"
              }
          end
        end)

      {:ok, %{board | pins: pins}}
    else
      _ -> invalid(:invalid_history, "Pin refresh is outside the admitted room history")
    end
  end

  defp refresh(board, {:unavailable, ids, checked_at})
       when is_list(ids) and length(ids) <= 16 and is_integer(checked_at) do
    pins =
      Enum.map(board.pins, fn pin ->
        if pin.id in ids,
          do: %{pin | checked_at: checked_at, error: "Refresh unavailable"},
          else: pin
      end)

    {:ok, %{board | pins: pins}}
  end

  defp refresh(_, _),
    do: invalid(:invalid_history, "Pin refresh is outside the admitted room history")

  defp one_result(%{panels: [%{id: id} = result]} = history) do
    with true <- history?(history) and result?(result),
         {:ok, [metric]} <- Panels.select([id]),
         true <- result.display_unit == metric.display_unit,
         true <- result.aggregation == aggregation(metric.type),
         true <- history_series?(result.chart, history) do
      normalized =
        Map.take(result, [
          :id,
          :title,
          :status,
          :chart,
          :digests,
          :display_unit,
          :aggregation,
          :series_shown,
          :series_total,
          :freshness_ms,
          :markers,
          :error
        ])

      {:ok, metric, normalized}
    end
  end

  defp one_result(_), do: :error

  defp history?(%{range: range, start_ms: first, end_ms: last, step_ms: step} = history) do
    expected = %{"5m" => {300_000, 5_000}, "15m" => {900_000, 15_000}, "1h" => {3_600_000, 60_000}}

    is_integer(first) and is_integer(last) and first >= 0 and last <= 253_402_300_799_999 and
      Map.get(expected, range) == {last - first, step} and
      is_integer(Map.get(history, :queried_at, last))
  end

  defp history?(_), do: false

  defp result?(
         %{
           id: id,
           status: status,
           chart: chart,
           digests: digests,
           display_unit: unit,
           aggregation: aggregation,
           series_shown: shown,
           series_total: total
         } = result
       ) do
    text?(id, 128) and
      status in [:available, :unavailable, :refused, :not_queried] and
      chart?(chart) and digests?(digests, status) and
      text?(unit, 32) and text?(aggregation, 64) and counts?(shown, total) and
      byte_size(:erlang.term_to_binary(result)) <= 32_768
  end

  defp result?(_), do: false

  defp chart?(nil), do: true

  defp chart?(%Chart{} = chart),
    do:
      match?({:ok, _}, Chart.new(Map.to_list(Map.from_struct(chart)))) and
        Enum.all?(chart.series, &(length(&1.points) <= 61))

  defp chart?(_), do: false

  defp digests?(digests, status) when is_list(digests) do
    length(digests) <= 8 and (status != :available or digests != []) and
      Enum.all?(digests, &(is_binary(&1) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, &1)))
  end

  defp digests?(_, _), do: false
  defp text?(value, max), do: is_binary(value) and String.valid?(value) and byte_size(value) <= max

  defp counts?(shown, total),
    do:
      is_integer(shown) and shown in 0..8 and is_integer(total) and total >= shown and
        total <= 65_536

  defp history_series?(nil, _), do: true

  defp history_series?(chart, history) do
    seconds = div(history.end_ms - history.start_ms, 1_000)
    step = div(history.step_ms, 1_000)
    expected = Enum.to_list(-seconds..0//step)
    Enum.all?(chart.series, fn series -> Enum.map(series.points, &elem(&1, 0)) == expected end)
  end

  defp aggregation(:counter), do: "rate per step"
  defp aggregation(:gauge), do: "last value per step"
  defp aggregation(:histogram), do: "p95 per step"
  defp pin_id(metric, range), do: "pin-#{metric}-#{range}"
  defp replace(pins, pin), do: Enum.map(pins, &if(&1.id == pin.id, do: pin, else: &1))

  defp layout?(%{"positions" => positions, "viewport" => viewport} = layout, ids)
       when map_size(layout) == 2 and is_list(positions) and length(positions) <= 48 do
    keys = Enum.map(positions, &if(is_map(&1), do: &1["id"]))

    length(keys) == length(Enum.uniq(keys)) and
      Enum.all?(positions, &position?(&1, ids)) and viewport?(viewport)
  end

  defp layout?(_, _), do: false

  defp position?(%{"id" => id, "x" => x, "y" => y} = value, ids) do
    Map.keys(value) -- ~w(id x y width height) == [] and id in ids and
      coordinate?(x, 20_000) and coordinate?(y, 20_000) and dimensions?(value, id)
  end

  defp position?(_, _), do: false

  defp dimensions?(%{"width" => w, "height" => h}, "pin-" <> _),
    do: is_number(w) and w >= 300 and w <= 800 and is_number(h) and h >= 200 and h <= 600

  defp dimensions?(value, _),
    do: not Map.has_key?(value, "width") and not Map.has_key?(value, "height")

  defp viewport?(%{"x" => x, "y" => y, "zoom" => zoom} = value),
    do:
      map_size(value) == 3 and coordinate?(x, 100_000) and coordinate?(y, 100_000) and
        is_number(zoom) and zoom >= 0.25 and zoom <= 2

  defp viewport?(_), do: false
  defp coordinate?(value, limit), do: is_number(value) and abs(value) <= limit
  defp invalid(code, message), do: {:error, Error.new(code, :workbench, message)}
end
