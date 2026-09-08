defmodule Wotex.Lab.MetricsDatasetTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Dataset, History, Query, Snapshot}

  @t0 1_700_000_000_000
  @t1 @t0 + 5_000
  @t2 @t0 + 10_000
  @scope %{instance: "lab-1", session: "session-1"}

  test "freezes an immutable masked dataset with exact query and watermark provenance" do
    history = start_supervised!({History, id: :dataset, instance: "lab-1"})
    put(history, 1, 0, 10)
    put(history, 3, 10_000, 30)
    query = query!()

    assert {:ok, dataset} = Dataset.freeze(history, query, experiment: "latency-review")
    assert dataset.schema_version == "1.0.0"
    assert dataset.id == dataset.digest
    assert String.starts_with?(dataset.digest, "sha256:")
    assert dataset.experiment == "latency-review"
    assert dataset.query.digest == Query.digest(query)
    assert dataset.source.instance == "lab-1"
    assert dataset.source.metric == "nx_queue_depth"
    assert dataset.unit == "count"
    assert dataset.watermark.history_sequence == 2
    assert dataset.watermark.count == 2
    assert dataset.row_count == 3
    assert dataset.split == %{status: "unsplit", strategy: "none"}
    assert dataset.missing_policy =~ "never fill with zero"

    assert [
             %{timestamp_ms: @t0, value: 10, mask: 1, quality: ["observed"]},
             %{timestamp_ms: @t1, value: nil, mask: 0, quality: ["missing"]},
             %{timestamp_ms: @t2, value: 30, mask: 1, quality: quality}
           ] = dataset.rows

    assert "gap" in quality
    assert %{timestamp_ms: @t2, kind: "gap"} in dataset.markers
    assert hd(dataset.transforms).downsampling == "none beyond the admitted query aggregation"

    assert {:ok, same} = Dataset.freeze(history, query, experiment: "latency-review")
    assert same == dataset

    exported = Dataset.to_map(dataset)
    assert exported["digest"] == dataset.digest
    assert get_in(exported, ["rows", Access.at(1), "mask"]) == 0
    assert get_in(exported, ["rows", Access.at(1), "value"]) == nil
    assert get_in(exported, ["query", "quantile"]) == nil
    assert is_binary(JSON.encode!(exported))
  end

  test "a later history write cannot mutate an exported dataset and changes the watermark identity" do
    history = start_supervised!({History, id: :immutable, instance: "lab-1"})
    put(history, 1, 0, 10)
    query = query!()

    assert {:ok, before} = Dataset.freeze(history, query, experiment: "immutable-review")
    put(history, 2, 15_000, 90)
    assert {:ok, after_write} = Dataset.freeze(history, query, experiment: "immutable-review")

    assert before.rows == after_write.rows
    assert before.watermark.history_sequence == 1
    assert after_write.watermark.history_sequence == 2
    refute before.digest == after_write.digest

    assert before.rows == [
             %{timestamp_ms: @t0, value: 10, mask: 1, quality: ["observed"]},
             %{timestamp_ms: @t1, value: nil, mask: 0, quality: ["missing"]},
             %{timestamp_ms: @t2, value: nil, mask: 0, quality: ["missing"]}
           ]
  end

  test "scope, descriptors, options and output bounds are revalidated at the freeze boundary" do
    history = start_supervised!({History, id: :refusal, instance: "lab-1"})
    put(history, 1, 0, 10)
    query = query!()

    assert {:error, %Error{code: :invalid_experiment}} =
             Dataset.freeze(history, query, experiment: "Not An ID")

    assert {:error, %Error{code: :invalid_options}} =
             Dataset.freeze(history, query, experiment: "one", experiment: "two")

    assert {:error, %Error{code: :invalid_step}} =
             Dataset.freeze(history, %{query | step_ms: 0}, experiment: "review")

    denied = %{query | scope: %{instance: "lab-2", session: "session-1"}}

    assert {:error, %Error{code: :scope_denied}} =
             Dataset.freeze(history, denied, experiment: "review")

    tiny = %{query | limits: %{query.limits | output_bytes: 1}}

    assert {:error, %Error{code: :output_too_large}} =
             Dataset.freeze(history, tiny, experiment: "review")

    unbound = start_supervised!({History, id: :unbound_dataset})

    assert {:error, %Error{code: :scope_unbound}} =
             Dataset.freeze(unbound, query, experiment: "review")

    :ok = stop_supervised({History, :refusal})

    assert {:error, %Error{code: :history_unavailable}} =
             Dataset.freeze(history, query, experiment: "review")
  end

  defp query! do
    {:ok, query} =
      Query.new(
        scope: @scope,
        metric: :nx_queue_depth,
        aggregation: :last,
        start_at: DateTime.from_unix!(@t0, :millisecond),
        end_at: DateTime.from_unix!(@t0 + 10_000, :millisecond),
        step_ms: 5_000
      )

    query
  end

  defp put(history, sequence, offset, value) do
    {:ok, snapshot} =
      Snapshot.new(%{
        source: :collector,
        instance_slot: 0,
        sequence: sequence,
        monotonic_ms: offset,
        wall_time_ms: @t0 + offset,
        identity: %{started_at: 1, generation: 0},
        series: [
          %{
            name: "wotex_lab_nx_queue_depth",
            type: :gauge,
            labels: [{"profile", "test"}],
            sample: %{value: value}
          }
        ]
      })

    assert {:ok, _admission} = History.put(history, snapshot)
  end
end
