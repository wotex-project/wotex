defmodule Wotex.Lab.Island.Canvas do
  @moduledoc false

  @node_fields ~w(id kind title identity value unit status detail x y)
  @edge_fields ~w(id source target label kind target_handle)
  @limits %{
    "id" => 128,
    "title" => 128,
    "identity" => 256,
    "value" => 128,
    "unit" => 32,
    "status" => 32,
    "detail" => 128
  }

  @doc false
  @spec validate(map()) :: :ok | {:error, :invalid_island_prop}
  def validate(%{"nodes" => nodes, "edges" => edges} = props) do
    ids = Enum.map(nodes, &field(&1, "id"))
    edge_ids = Enum.map(edges, &field(&1, "id"))
    pins = Map.get(props, "pins", [])
    pin_ids = Enum.map(pins, &field(&1, "id"))

    if unique?(ids) and unique?(edge_ids) and Enum.all?(nodes, &node?/1) and
         Enum.all?(edges, &edge?(&1, ids)) and unique?(ids ++ pin_ids) and
         Enum.all?(pins, &pin?/1) and Enum.all?(Map.get(props, "view", []), &view?/1) and
         Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, Map.get(props, "layout_revision", "0")) and
         Map.get(props, "selection", "") in ["" | ids ++ pin_ids],
       do: :ok,
       else: {:error, :invalid_island_prop}
  end

  defp field(value, key) when is_map(value), do: Map.get(value, key)
  defp field(_, _), do: nil
  defp unique?(ids), do: length(ids) == MapSet.size(MapSet.new(ids))

  defp node?(node) when is_map(node) do
    exact?(Map.delete(node, "operations"), @node_fields) and
      operations?(Map.get(node, "operations", [])) and
      Enum.all?(@limits, fn {key, limit} -> text?(node[key], limit) end) and
      identifier?(node["id"]) and node["kind"] in ~w(thing process entry) and
      coordinate?(node["x"]) and coordinate?(node["y"])
  end

  defp node?(_), do: false

  defp operations?(operations) when is_list(operations),
    do:
      length(operations) <= 3 and unique?(operations) and
        Enum.all?(operations, &(&1 in ~w(read observe pause)))

  defp operations?(_), do: false

  defp edge?(edge, ids) when is_map(edge) do
    exact?(edge, @edge_fields) and identifier?(edge["id"]) and
      edge["source"] in ids and edge["target"] in ids and
      text?(edge["label"], 128) and edge["kind"] in ~w(input proposal) and
      edge["target_handle"] in ~w(temperature power input)
  end

  defp edge?(_, _), do: false

  defp pin?(%{"kind" => "run"} = pin) do
    exact?(
      pin,
      ~w(kind id title run_id record_digest chart_index source_mode state started_at unit mark outcome series x y width height)
    ) and
      run_identity?(pin) and run_metadata?(pin) and outcome?(pin["outcome"]) and
      pin_geometry?(pin) and run_series?(pin["series"])
  end

  defp pin?(pin) when is_map(pin) do
    exact?(
      pin,
      ~w(id title metric source range unit aggregation state auto_refresh end_ms series x y width height)
    ) and
      pin_identity?(pin) and is_boolean(pin["auto_refresh"]) and pin_geometry?(pin) and
      pin_series?(pin["series"])
  end

  defp pin?(_), do: false

  defp run_identity?(pin) do
    identifier?(pin["id"]) and identifier?(pin["run_id"]) and
      text?(pin["record_digest"], 71) and
      Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, pin["record_digest"]) and
      is_integer(pin["chart_index"]) and pin["chart_index"] in 0..7
  end

  defp run_metadata?(pin) do
    text?(pin["title"], 128) and text?(pin["source_mode"], 64) and
      text?(pin["state"], 64) and text?(pin["unit"], 32) and
      pin["mark"] in ~w(line point area) and timestamp?(pin["started_at"])
  end

  defp run_series?(series),
    do: pin_series?(series, 512) and Enum.sum(Enum.map(series, &length(&1["points"]))) <= 512

  defp pin_identity?(pin) do
    identifier?(pin["id"]) and identifier?(pin["metric"]) and
      Enum.all?(
        [{"title", 128}, {"source", 64}, {"unit", 32}, {"aggregation", 64}, {"state", 64}],
        fn
          {key, limit} -> text?(pin[key], limit)
        end
      ) and pin["range"] in ~w(5m 15m 1h) and is_integer(pin["end_ms"]) and
      abs(pin["end_ms"]) <= 9_007_199_254_740_991
  end

  defp pin_geometry?(pin),
    do:
      coordinate?(pin["x"]) and coordinate?(pin["y"]) and
        number_between?(pin["width"], 300, 800) and number_between?(pin["height"], 200, 600)

  defp pin_series?(series, limit \\ 61)

  defp pin_series?(series, limit) when is_list(series),
    do:
      length(series) <= 8 and unique?(Enum.map(series, &field(&1, "name"))) and
        Enum.all?(series, &series?(&1, limit))

  defp pin_series?(_, _), do: false

  defp series?(%{"name" => name, "points" => points} = value, limit) when is_list(points),
    do:
      map_size(value) == 2 and text?(name, 128) and length(points) <= limit and
        Enum.all?(points, &point?/1)

  defp series?(_, _), do: false

  defp outcome?(nil), do: true

  defp outcome?(value) when is_map(value),
    do:
      exact?(value, ~w(label value unit note)) and
        Enum.all?(~w(label value note), &text?(value[&1], 128)) and text?(value["unit"], 32)

  defp outcome?(_), do: false

  defp timestamp?(value) when is_binary(value) and byte_size(value) <= 32,
    do:
      Regex.match?(~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z\z/, value) and
        match?({:ok, _, 0}, DateTime.from_iso8601(value))

  defp timestamp?(_), do: false

  defp point?([x, y]),
    do:
      number_between?(x, -1.0e100, 1.0e100) and (is_nil(y) or number_between?(y, -1.0e100, 1.0e100))

  defp point?(_), do: false

  defp view?(%{"x" => x, "y" => y, "zoom" => zoom} = value),
    do:
      map_size(value) == 3 and number_between?(x, -100_000, 100_000) and
        number_between?(y, -100_000, 100_000) and number_between?(zoom, 0.25, 2)

  defp view?(_), do: false
  defp number_between?(value, low, high), do: is_number(value) and value >= low and value <= high
  defp exact?(value, keys), do: Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp text?(value, max), do: is_binary(value) and String.valid?(value) and byte_size(value) <= max
  defp coordinate?(value), do: is_number(value) and value >= -20_000 and value <= 20_000

  defp identifier?(value),
    do: text?(value, 128) and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/, value)
end
