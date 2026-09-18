defmodule WotexLabWorkbench.TensorWindowTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.DataSchema
  alias Wotex.Lab.Error
  alias Wotex.Nx.{Encoder, Feature, Row, Schema}
  alias WotexLabWorkbench.{Preview, Runs}

  test "wide, long batches are split and sliced before every host-list conversion" do
    {:ok, schema} =
      DataSchema.new(%{
        "type" => "array",
        "items" => %{"type" => "number"},
        "minItems" => 64,
        "maxItems" => 64
      })

    features =
      for i <- 1..40 do
        {:ok, feature} =
          Feature.new(
            name: "feature-#{i}",
            thing_id: "urn:test:preview",
            affordance_type: :property,
            affordance_name: "values-#{i}",
            data_schema: schema,
            missing: {:fill, -2.0}
          )

        feature
      end

    {:ok, schema} = Schema.new(features: features, max_rows: 250, max_width: 3_000)

    rows =
      for i <- 1..250 do
        {:ok, row} = Row.new(i, %{})
        row
      end

    {:ok, encoded} =
      Nx.with_default_backend(Nx.BinaryBackend, fn -> Encoder.encode(rows, schema) end)

    {summary, shapes} = trace_lists(fn -> Preview.tensor_summary(encoded, Nx.BinaryBackend) end)
    assert summary.rows == 250

    assert summary.preview_bounds == %{
             rows: 100,
             features: 32,
             total_features: 40,
             elements_per_feature: 32,
             truncated: true
           }

    assert length(summary.features) == 32 and length(summary.feature_order) == 32
    assert length(summary.preview) == 100
    assert length(shapes) == 65
    assert Enum.all?(shapes, &(&1 == {100, 32}))
    assert Enum.all?(summary.features, &(&1.observed == 0 and &1.filled == 3_200))

    assert Enum.all?(summary.preview, fn row ->
             length(row.cells) == 32 and
               Enum.all?(row.cells, fn cell ->
                 length(cell.value) == 32 and length(cell.mask) == 32 and
                   cell.text =~ "filled, mask 0"
               end)
           end)

    assert Runs.plain(Nx.iota({100, 100})) == Enum.to_list(0..31)
    assert Runs.plain(Nx.tensor(7)) == [7]
  end

  test "downsampling retains extrema without drawing across an omitted gap" do
    points = [
      {10, 0},
      {9, nil},
      {8, 1},
      {7, 8},
      {6, nil},
      {5, -5},
      {4, 2},
      {3, nil},
      {2, 3},
      {1, nil},
      {0, 4}
    ]

    sampled = Preview.downsample(points, 5)
    assert sampled.interval == 11 and sampled.dropped == 6
    assert sampled.points == [{9, nil}, {7, 8}, {6, nil}, {5, -5}, {3, nil}]

    for max <- [5, 10, 30, 100] do
      raw = for i <- 1..500, do: {i, if(rem(i, 4) == 0, do: nil, else: rem(i, 17))}
      sample = Preview.downsample(raw, max)
      assert length(sample.points) <= max

      for [{left, value}, {right, next}] <- Enum.chunk_every(sample.points, 2, 1, :discard),
          is_number(value) and is_number(next) do
        assert Enum.all?(Enum.slice(raw, left - 1, right - left + 1), &is_number(elem(&1, 1)))
      end
    end

    assert Preview.downsample(Enum.map(1..20, &{&1, nil}), 5).points == [{1, nil}]
    assert Preview.downsample([{1, 1}, {2, 2}], 2).method == "none"

    for max <- [0, 1, 2.5, 2_001, "100"] do
      assert {:error, %Error{code: :invalid_preview_budget}} = Preview.downsample([], max)
    end
  end

  defp trace_lists(fun) do
    tracer = spawn_link(fn -> collect_shapes([]) end)
    :erlang.trace_pattern({Nx, :to_list, 1}, true, [:local])
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    try do
      result = fun.()
      :erlang.trace(self(), false, [:call])
      reference = :erlang.trace_delivered(self())

      receive do
        {:trace_delivered, _, ^reference} -> :ok
      after
        1_000 -> flunk("trace delivery did not complete")
      end

      send(tracer, {:report, self()})

      receive do
        {:shapes, shapes} -> {result, shapes}
      after
        1_000 -> flunk("shape collector did not complete")
      end
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern({Nx, :to_list, 1}, false, [:local])
      Process.unlink(tracer)
      if Process.alive?(tracer), do: Process.exit(tracer, :kill)
    end
  end

  defp collect_shapes(shapes) do
    receive do
      {:trace, _, :call, {Nx, :to_list, [tensor]}} -> collect_shapes([Nx.shape(tensor) | shapes])
      {:report, caller} -> send(caller, {:shapes, Enum.reverse(shapes)})
    end
  end
end
