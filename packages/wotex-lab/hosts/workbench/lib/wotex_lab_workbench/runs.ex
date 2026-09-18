defmodule WotexLabWorkbench.Runs do
  @moduledoc """
  Helpers shared by the experiment runners.

  Runners return plain, JSON-compatible values: structs from the WoTEx
  packages are converted with `plain/1` (string keys, atoms as strings,
  tensors as their bounded list form), durations are measured around the
  public calls, and timeseries are derived from the bounded tensor preview
  so the browser never receives more than the preview window.
  """

  alias WotexLabWorkbench.Preview

  @max_plain_depth 6

  @doc "Measures a function; returns its result and the elapsed milliseconds."
  @spec measure((-> result)) :: {result, non_neg_integer()} when result: term()
  def measure(fun) when is_function(fun, 0) do
    start = System.monotonic_time(:millisecond)
    result = fun.()
    {result, max(System.monotonic_time(:millisecond) - start, 0)}
  end

  @doc "Converts a value to a bounded, JSON-compatible form."
  @spec plain(term(), non_neg_integer()) :: term()
  def plain(value, depth \\ 0)
  def plain(_, depth) when depth > @max_plain_depth, do: "…"

  def plain(%Nx.Tensor{} = tensor, _) do
    tensor
    |> Nx.flatten()
    |> Nx.slice_along_axis(0, min(Nx.size(tensor), 32))
    |> Nx.to_flat_list()
  end

  def plain(%DateTime{} = value, _), do: DateTime.to_iso8601(value)
  def plain(%MapSet{} = value, depth), do: plain(MapSet.to_list(value), depth + 1)
  def plain(%_{} = value, depth), do: plain(Map.from_struct(value), depth + 1)

  def plain(value, depth) when is_map(value) do
    Map.new(value, fn {key, inner} -> {to_string(key), plain(inner, depth + 1)} end)
  end

  def plain(value, depth) when is_list(value),
    do: Enum.map(Enum.take(value, 64), &plain(&1, depth + 1))

  def plain(value, _) when is_tuple(value),
    do: Enum.map(Tuple.to_list(value), &plain(&1, @max_plain_depth))

  def plain(value, _) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  def plain(value, _)
      when is_pid(value) or is_reference(value) or is_function(value) or is_port(value),
      do: "opaque"

  def plain(value, _), do: value

  @doc "Builds one series per feature from a tensor preview; filled rows become gaps."
  @spec timeseries(map()) :: [map()]
  def timeseries(%{feature_order: features, preview: rows} = tensor) do
    features
    |> Enum.with_index()
    |> Enum.map(fn {feature, index} ->
      unit = Map.get(Enum.at(tensor.features, index), :unit, "none")

      points =
        Enum.map(rows, fn row ->
          cell = Enum.at(row.cells, index)
          {row.timestamp, if(cell.mask == 1 and is_number(cell.value), do: cell.value, else: nil)}
        end)

      %{
        name: "#{feature} (#{unit})",
        unit: unit,
        source: "encoded batch preview",
        points: points,
        method: "none",
        interval: nil,
        dropped: 0
      }
    end)
  end

  @doc "Builds a bounded series from raw points with downsampling recorded."
  @spec series(String.t(), String.t(), String.t(), [Preview.point()]) :: map()
  def series(name, unit, source, points) do
    # The fixed default budget admits min/max plus gap sentinels; no caller
    # can reduce it below the downsampler's safe minimum here.
    sampled = Preview.downsample(points)

    %{
      name: name,
      unit: unit,
      source: source,
      points: sampled.points,
      method: sampled.method,
      interval: sampled.interval,
      dropped: sampled.dropped
    }
  end

  @doc "An assertion outcome row."
  @spec assertion(String.t(), boolean() | :not_run, String.t()) :: map()
  def assertion(id, :not_run, note), do: %{id: id, status: :not_run, note: note}
  def assertion(id, true, note), do: %{id: id, status: :pass, note: note}
  def assertion(id, false, note), do: %{id: id, status: :fail, note: note}
end
