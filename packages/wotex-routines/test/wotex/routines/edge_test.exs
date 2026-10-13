defmodule Wotex.Routines.EdgeTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Compiler, Edge, Error, Kernel, Limits, Profile}

  setup_all do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, limits} = Limits.new(corpus["limits"])

    {:ok, profile} =
      Profile.new(%{
        "source_bytes" => 65_536,
        "source_depth" => 32,
        "expanded_nodes" => 64,
        "predicate_nodes" => 64,
        "invocation_depth" => 4,
        "parallel_width" => 4,
        "effects" => 16,
        "waits" => 16,
        "active_definitions" => 64,
        "active_runs" => 64,
        "pending_work" => 64,
        "run_ms" => 86_400_000
      })

    {:ok, date, _} = DateTime.from_iso8601(corpus["fact"]["source_time"])
    utc = DateTime.to_unix(date, :millisecond) + 500
    %{corpus: corpus, limits: limits, profile: profile, utc: utc}
  end

  test "first samples only baseline, new reports debounce, and hysteresis preserves the candidate",
       c do
    c = fixture(c)
    baseline = advance(c, nil, 1, 10, 1000)
    assert baseline["reason"] == "baseline"
    assert baseline["edge"]["baseline"] == false
    candidate = advance(c, baseline["edge"], 2, 20, 3000)
    assert candidate["reason"] == "debouncing"
    assert candidate["edge"]["candidate_since_ms"] == 20
    duplicate = advance(c, candidate["edge"], 2, 119, 3000, 20)
    assert duplicate["reason"] == "duplicate"
    assert duplicate["eligible"] == false
    almost = advance(c, duplicate["edge"], 3, 119, 2000)
    assert almost["reason"] == "debouncing"
    ready = advance(c, almost["edge"], 4, 120, 2000)
    assert ready["eligible"] == true
    assert ready["edge"]["baseline"] == true
    assert ready["edge"]["cooldown_until_ms"] == 320
    assert ready["edge"]["last_original"] == "original:4"

    schema =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("schemas/wro-02-execution.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, ready) == :ok
    assert ExJsonSchema.Validator.validate(schema, ready["edge"]) == :ok
  end

  test "inactive and unknown reports break stability; restored and first active reports never fire",
       c do
    c = fixture(c)
    first_active = advance(c, nil, 1, 10, 3000)
    assert first_active["eligible"] == false
    baseline = advance(c, first_active["edge"], 2, 20, 1000)
    candidate = advance(c, baseline["edge"], 3, 30, 3000)
    interrupted = advance(c, candidate["edge"], 4, 50, 1000)
    assert interrupted["edge"]["candidate_since_ms"] == nil
    unqualified = with_sample(c, 5, 60, 3000)

    unqualified = %{
      unqualified
      | snapshot: put_in(unqualified.snapshot, ["facts", "sensor", "continuity"], "baseline")
    }

    assert {:ok, reset} = evaluate(unqualified, interrupted["edge"])
    assert reset["reason"] == "unqualified"
    assert reset["edge"]["baseline"] == nil
    resumed = advance(c, reset["edge"], 6, 200, 3000)
    assert resumed["reason"] == "baseline"
    assert resumed["eligible"] == false
  end

  test "cooldown consumes a suppressed transition with no delayed catch-up", c do
    c = fixture(c, "rising", 0)
    baseline = advance(c, nil, 1, 10, 1000)
    ready = advance(c, baseline["edge"], 2, 20, 3000)
    inactive = advance(c, ready["edge"], 3, 30, 1000)
    suppressed = advance(c, inactive["edge"], 4, 40, 3000)
    assert suppressed["reason"] == "cooldown"
    later = advance(c, suppressed["edge"], 5, 500, 3000)
    assert later["eligible"] == false
    inactive = advance(c, later["edge"], 6, 510, 1000)
    assert advance(c, inactive["edge"], 7, 520, 3000)["eligible"] == true
  end

  test "source and time replacement reset; receipt/sequence regressions cannot form edges", c do
    c = fixture(c, "rising", 0)
    baseline = advance(c, nil, 7, 100, 1000)

    for {kind, field, value} <- [
          {:time, "epoch", "boot:2"},
          {:time, "clock_generation", "clock:2"},
          {:binding, "source_epoch", "connection:2"},
          {:binding, "source_id", "sensor:2"},
          {:binding, "source_time_basis", "sha256:" <> String.duplicate("9", 64)}
        ] do
      sample = with_sample(c, 8, 110, 3000)
      sample = replace(sample, kind, field, value)
      assert {:ok, reset} = evaluate(sample, baseline["edge"])
      assert reset["eligible"] == false
    end

    assert advance(c, baseline["edge"], 6, 110, 3000)["reason"] == "unqualified"
    assert advance(c, baseline["edge"], 8, 110, 3000, 90)["reason"] == "unqualified"
    assert advance(c, baseline["edge"], 8, 99, 3000)["reason"] == "unqualified"
    same = with_sample(c, 7, 100, 3000)
    assert {:error, %Error{code: :conflicting_edge_fact}} = evaluate(same, baseline["edge"])
    expired = with_sample(c, 7, 1100, 1000, 100)
    assert {:ok, reset} = evaluate(expired, baseline["edge"])
    assert reset["reason"] == "unqualified"
  end

  test "falling integer and boolean edges use their own inactive baseline", c do
    for boolean <- [false, true] do
      c = fixture(c, "falling", 0, boolean)
      {inactive, active} = if boolean, do: {true, false}, else: {3000, 1000}
      baseline = advance(c, nil, 1, 10, inactive)
      assert baseline["edge"]["baseline"] == false
      assert advance(c, baseline["edge"], 2, 20, active)["eligible"] == true
    end
  end

  test "kernel retains no-edge and skipped-busy without catching up suppressed roots", c do
    c = fixture(c, "rising", 0)
    c = with_sample(c, 1, 10, 1000)
    prior = %{"original" => nil, "busy" => nil, "edge" => nil}
    assert {:ok, baseline} = kernel(c, prior)
    assert baseline["outcome"] == "no-edge"
    c = with_sample(c, 2, 20, 3000)
    assert {:ok, started} = kernel(c, %{prior | "edge" => baseline["edge"]})
    assert started["outcome"] == "running"
    c = with_sample(c, 3, 300, 1000)

    assert {:ok, inactive} =
             kernel(c, %{prior | "edge" => started["edge"], "busy" => started["run"]})

    c = with_sample(c, 4, 310, 3000)

    assert {:ok, skipped} =
             kernel(c, %{prior | "edge" => inactive["edge"], "busy" => started["run"]})

    assert skipped["outcome"] == "skipped-busy"
    assert skipped["edge"]["last_original"] == "original:4"
    c = with_sample(c, 5, 600, 3000)
    assert {:ok, no_catchup} = kernel(c, %{prior | "edge" => skipped["edge"]})
    assert no_catchup["outcome"] == "no-edge"
  end

  test "reclassifying a retained sample as unusable clears qualification before identity checks",
       c do
    c = fixture(c, "rising", 0)
    baseline = advance(c, nil, 1, 10, 1000)
    sample = with_sample(c, 1, 20, 1000, 10)

    sample = %{
      sample
      | snapshot: put_in(sample.snapshot, ["facts", "sensor", "quality"], "unknown")
    }

    assert {:ok, reset} = evaluate(sample, baseline["edge"])
    assert reset["reason"] == "unqualified"
    assert reset["edge"]["baseline"] == nil
    assert reset["edge"]["last_fact_digest"] == baseline["edge"]["last_fact_digest"]
    next = advance(c, reset["edge"], 2, 30, 3000)
    assert next["reason"] == "baseline"
    assert next["eligible"] == false
  end

  test "malformed retained edges and foreign fact events refuse without replacing state", c do
    c = fixture(c)
    baseline = advance(c, nil, 1, 10, 1000)
    assert Edge.to_map(baseline["edge"], c.program, c.profile, c.limits) == {:ok, baseline["edge"]}

    for edge <- [
          Map.delete(baseline["edge"], "baseline"),
          %{baseline["edge"] | "candidate_since_ms" => 11},
          %{baseline["edge"] | "last_fact_id" => nil},
          struct!(Edge, data: nil)
        ] do
      assert {:error, %Error{}} = Edge.new(edge, c.program, c.profile, c.limits)
    end

    c = with_sample(c, 2, 20, 3000)

    assert {:error, %Error{code: :foreign_edge_fact}} =
             evaluate(%{c | event: %{c.event | "fact_id" => "other"}}, baseline["edge"])
  end

  defp fixture(c, direction \\ "rising", debounce \\ 100, boolean \\ false) do
    basis = Enum.at(c.corpus["bases"], if(boolean, do: 1, else: 0))

    hysteresis =
      if boolean,
        do: nil,
        else:
          if(direction == "rising",
            do: %{"enter" => 2500, "exit" => 1500},
            else: %{"enter" => 1500, "exit" => 2500}
          )

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "edge",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ["sensor"],
      "trigger" => %{
        "kind" => "edge",
        "binding" => "sensor",
        "direction" => direction,
        "debounce_ms" => debounce,
        "cooldown_ms" => 200,
        "hysteresis" => hysteresis
      },
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => %{"id" => "pause", "kind" => "delay", "duration_ms" => 1000},
      "overlap" => "reject",
      "run_ms" => 10_000
    }

    context = %{
      "registry" => c.corpus["registry"],
      "bases" => c.corpus["bases"],
      "bindings" => %{
        "sensor" => %{
          "basis" => Map.take(basis, ~w(id version semantic_digest)),
          "thing_id" => c.corpus["fact"]["thing_id"],
          "resource_roles" => %{}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, program} = Compiler.compile(source, context, c.profile, c.limits)
    Map.merge(c, %{program: program, selected_basis: basis})
  end

  defp with_sample(c, sequence, elapsed, value, receipt \\ nil) do
    receipt = receipt || elapsed

    fact = %{
      c.corpus["fact"]
      | "id" => "sample:#{sequence}",
        "sequence" => sequence,
        "receipt_ms" => receipt,
        "expires_ms" => receipt + 1000,
        "value" => value,
        "unit" => c.selected_basis["value"]["unit"],
        "profile_digest" => c.selected_basis["semantic_digest"],
        "affordance_type" => c.selected_basis["affordance"]["type"],
        "affordance_name" => c.selected_basis["affordance"]["name"]
    }

    snapshot = %{
      "id" => "snapshot:#{sequence}",
      "membership_generation" => "membership:1",
      "active_programs" => [c.program.data["ir_digest"]],
      "resource_revisions" => %{fact["thing_id"] => 1},
      "binding_bases" => %{
        "sensor" => Map.take(fact, ~w(profile_digest source_id source_epoch source_time_basis))
      },
      "facts" => %{"sensor" => fact}
    }

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => elapsed,
      "clock_generation" => "clock:1",
      "utc_low_ms" => c.utc,
      "utc_high_ms" => c.utc
    }

    event = %{
      "kind" => "fact",
      "original" => "original:#{sequence}",
      "program_digest" => c.program.data["ir_digest"],
      "binding" => "sensor",
      "fact_id" => fact["id"]
    }

    Map.merge(c, %{snapshot: snapshot, time: time, event: event})
  end

  defp advance(c, edge, sequence, elapsed, value, receipt \\ nil) do
    c = with_sample(c, sequence, elapsed, value, receipt)
    assert {:ok, result} = evaluate(c, edge)
    result
  end

  defp evaluate(c, edge),
    do: Edge.advance(c.program, c.event, c.snapshot, c.time, edge, c.profile, c.limits)

  defp kernel(c, prior),
    do: Kernel.advance(c.program, c.event, c.snapshot, c.time, prior, c.profile, c.limits)

  defp replace(c, :time, "epoch", value),
    do: %{
      c
      | time: Map.put(c.time, "epoch", value),
        snapshot: put_in(c.snapshot, ["facts", "sensor", "receipt_epoch"], value)
    }

  defp replace(c, :time, field, value), do: %{c | time: Map.put(c.time, field, value)}

  defp replace(c, :binding, field, value),
    do: %{
      c
      | snapshot:
          c.snapshot
          |> put_in(["binding_bases", "sensor", field], value)
          |> put_in(["facts", "sensor", field], value)
    }
end
