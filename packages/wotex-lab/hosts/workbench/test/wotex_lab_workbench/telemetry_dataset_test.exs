defmodule WotexLabWorkbench.TelemetryDatasetTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Island.CanonicalJSON
  alias WotexLabWorkbench.{Report, TelemetryDataset}

  @now ~U[2026-10-23 00:00:00Z]

  test "a capture and its report preserve more than 64 rows, nulls and exact content identity" do
    live = capture(128)
    {:ok, dataset} = TelemetryDataset.new("dataset-1", "owner", [limit: 128], live, @now)
    encoded = TelemetryDataset.to_map(dataset)
    assert dataset.rows == 128
    assert length(encoded["samples"]) == 128
    assert hd(encoded["samples"])["duration_ms"] == nil
    assert List.last(encoded["samples"])["sequence"] == 128
    refute Map.has_key?(hd(encoded["samples"]), "scope")

    content = Map.drop(encoded, ~w(id digest frozen_at))
    {:ok, bytes} = CanonicalJSON.encode(content)
    assert Digest.bytes(bytes) == dataset.digest

    report = Report.build(%{id: "owner", runs: [], datasets: [dataset], formal: [], policy: []})
    {:ok, report} = Report.encode(report)
    assert hd(JSON.decode!(report)["datasets"])["samples"] == encoded["samples"]
  end

  test "query, source, watermark and loss change the digest; presentation identity and time do not" do
    live = capture(2)
    {:ok, original} = TelemetryDataset.new("one", "owner", [], live, @now)
    {:ok, again} = TelemetryDataset.new("two", "owner", [], live, DateTime.add(@now, 1))
    assert original.digest == again.digest

    for {query, changed} <- [
          {[limit: 2], live},
          {[], %{live | watermark: 3}},
          {[], %{live | loss: %{overwritten: 1}}},
          {[], %{live | truncated: true}}
        ] do
      assert {:ok, other} = TelemetryDataset.new("one", "owner", query, changed, @now)
      refute original.digest == other.digest
    end
  end

  test "cross-scope, malformed, empty and excessive captures are refused" do
    live = capture(2)
    [first, second] = live.samples

    for changed <- [
          %{},
          %{live | samples: []},
          %{live | samples: [nil]},
          %{live | samples: [Map.put(first, :scope, "another"), second]},
          %{live | samples: [Map.put(first, :duration_ms, -1), second]},
          %{live | samples: [Map.put(first, :event, :unknown), second]},
          %{live | samples: [second, first]},
          %{live | samples: [first, first]},
          capture(2_001)
        ] do
      assert {:error, %Error{code: :invalid_dataset}} =
               TelemetryDataset.new("one", "owner", [], changed, @now)
    end

    assert {:error, %Error{code: :dataset_too_large}} =
             TelemetryDataset.new("one", "owner", [], capture(2_000), @now)
  end

  defp capture(count) do
    %{
      source: :live,
      samples:
        for index <- 1..count do
          %{
            scope: "owner",
            sequence: index,
            at: 1_792_713_600_000 + index,
            component: :scenario,
            operation: :inference,
            event: :measurement,
            duration_ms: if(rem(index, 2) == 0, do: 12.5, else: nil),
            outcome: :ok
          }
        end,
      interval: %{from: 1_792_713_600_000, to: 1_792_713_660_000},
      watermark: count,
      unit: "ms",
      loss: %{overwritten: 0, capacity: 2_000, retained: count},
      truncated: false
    }
  end
end
