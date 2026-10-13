defmodule Wotex.Routines.EvaluationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Compiler, Error, Evaluation, Limits, Profile, Snapshot, Time}

  @profile %{
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
  }
  @source %{
    "format" => "wotex.routines.source@1",
    "profile" => "bounded-composition@1",
    "id" => "measurement-check",
    "revision" => "1",
    "parameters" => %{},
    "bindings" => ["sensor"],
    "trigger" => %{"kind" => "manual"},
    "condition" => %{"op" => "gt", "binding" => "sensor", "value" => 2000},
    "steps" => %{"id" => "end", "kind" => "noop"},
    "overlap" => "reject",
    "run_ms" => 1000
  }

  setup_all do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, limits} = Limits.new(corpus["limits"])
    {:ok, profile} = Profile.new(@profile)
    basis = hd(corpus["bases"])
    raw = %{corpus["fact"] | "received_at" => corpus["fact"]["source_time"]}

    binding = %{
      "basis" => Map.take(basis, ~w(id version semantic_digest)),
      "thing_id" => raw["thing_id"],
      "resource_roles" => %{}
    }

    context = %{
      "registry" => corpus["registry"],
      "bases" => corpus["bases"],
      "bindings" => %{"sensor" => binding},
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, program} = Compiler.compile(@source, context, profile, limits)

    snapshot = %{
      "id" => "snapshot:1",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{raw["thing_id"] => 1},
      "binding_bases" => %{
        "sensor" => Map.take(raw, ~w(profile_digest source_id source_epoch source_time_basis))
      },
      "facts" => %{"sensor" => raw}
    }

    {:ok, date, _} = DateTime.from_iso8601(raw["source_time"])
    utc = DateTime.to_unix(date, :millisecond)

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => 20,
      "clock_generation" => "clock:1",
      "utc_low_ms" => utc + 500,
      "utc_high_ms" => utc + 500
    }

    %{
      corpus: corpus,
      limits: limits,
      profile: profile,
      context: context,
      program: program,
      snapshot: snapshot,
      time: time,
      utc: utc
    }
  end

  test "qualified exact scalar values produce truth and false without a trigger", context do
    assert evaluate(context, context.snapshot, context.time) == {:ok, true}

    assert evaluate(
             context,
             put_in(context.snapshot, ["facts", "sensor", "value"], 1000),
             context.time
           ) == {:ok, false}

    assert evaluate(context, put_in(context.snapshot, ["facts", "sensor"], nil), context.time) ==
             {:ok, "unknown"}

    {:ok, snapshot} =
      Snapshot.new(context.snapshot, context.program, context.profile, context.limits)

    assert Snapshot.to_map(snapshot, context.program, context.profile, context.limits) ==
             {:ok, context.snapshot}
  end

  test "quality, replay, continuity and identity cannot fabricate a current value", context do
    for {key, value} <- [
          {"quality", "invalid"},
          {"quality", "stale"},
          {"quality", "unknown"},
          {"replay", "retained"},
          {"replay", "replayed"},
          {"continuity", "baseline"},
          {"continuity", "lost"},
          {"source_epoch", "connection:old"},
          {"source_id", "foreign"},
          {"source_class", "protocol_response"},
          {"affordance_name", "other"},
          {"thing_id", "urn:workcell:other"}
        ] do
      snapshot = put_in(context.snapshot, ["facts", "sensor", key], value)
      assert evaluate(context, snapshot, context.time) == {:ok, "unknown"}
    end

    source = %{@source | "condition" => %{"op" => "not", "arg" => @source["condition"]}}
    {:ok, program} = Compiler.compile(source, context.context, context.profile, context.limits)
    snapshot = put_in(context.snapshot, ["facts", "sensor", "quality"], "unknown")

    assert Evaluation.evaluate(program, snapshot, context.time, context.profile, context.limits) ==
             {:ok, "unknown"}
  end

  test "receipt and source freshness use their separate exact boundaries", context do
    assert evaluate(context, context.snapshot, %{context.time | "elapsed_ms" => 9}) ==
             {:ok, "unknown"}

    assert evaluate(context, context.snapshot, %{context.time | "elapsed_ms" => 1010}) ==
             {:ok, "unknown"}

    assert evaluate(context, context.snapshot, %{context.time | "epoch" => "boot:2"}) ==
             {:ok, "unknown"}

    time = %{context.time | "utc_low_ms" => context.utc + 990, "utc_high_ms" => context.utc + 990}
    assert evaluate(context, context.snapshot, time) == {:ok, true}

    assert evaluate(context, context.snapshot, %{time | "utc_high_ms" => context.utc + 991}) ==
             {:ok, "unknown"}

    assert evaluate(context, context.snapshot, %{time | "utc_low_ms" => context.utc + 9}) ==
             {:ok, "unknown"}

    assert evaluate(context, context.snapshot, %{time | "utc_low_ms" => nil, "utc_high_ms" => nil}) ==
             {:ok, "unknown"}
  end

  test "timestamp presence cannot replace source-clock trust or selected basis", context do
    for {key, value} <- [
          {"source_time_trust", "untrusted"},
          {"source_time_trust", "unknown"},
          {"source_time_basis", "sha256:" <> String.duplicate("8", 64)}
        ] do
      snapshot = put_in(context.snapshot, ["facts", "sensor", key], value)
      assert evaluate(context, snapshot, context.time) == {:ok, "unknown"}
    end
  end

  test "compatible units convert exactly and unrelated dimensions remain unknown", context do
    unit = hd(context.corpus["conversions"])["to"]
    raw = %{context.snapshot["facts"]["sensor"] | "unit" => unit, "value" => 298_150}

    assert evaluate(context, put_in(context.snapshot, ["facts", "sensor"], raw), context.time) ==
             {:ok, true}

    assert evaluate(
             context,
             put_in(context.snapshot, ["facts", "sensor"], %{raw | "value" => 298_151}),
             context.time
           ) == {:ok, "unknown"}

    voltage = Enum.at(context.corpus["conversions"], 8)["from"]

    assert evaluate(
             context,
             put_in(context.snapshot, ["facts", "sensor"], %{
               raw
               | "unit" => voltage,
                 "value" => 3000
             }),
             context.time
           ) == {:ok, "unknown"}
  end

  test "complete snapshot and clock shapes reject missing or incoherent fields", context do
    assert {:error, %Error{code: :missing_field}} =
             Snapshot.new(
               %{context.snapshot | "facts" => %{}},
               context.program,
               context.profile,
               context.limits
             )

    assert {:error, %Error{code: :missing_field}} =
             Snapshot.new(
               %{context.snapshot | "resource_revisions" => %{}},
               context.program,
               context.profile,
               context.limits
             )

    assert {:error, %Error{code: :invalid_clock_interval}} =
             Time.new(%{context.time | "utc_high_ms" => context.utc - 1}, context.limits)

    assert {:error, %Error{}} = Time.new(%{context.time | "utc_low_ms" => nil}, context.limits)

    assert {:error, %Error{}} =
             Snapshot.new(
               struct!(Snapshot, data: nil),
               context.program,
               context.profile,
               context.limits
             )
  end

  test "an independent source AST oracle agrees with compiled nested three-valued predicates",
       context do
    literals = Enum.map([true, false, "unknown"], &%{"op" => "literal", "value" => &1})

    combinations =
      for left <- literals, right <- literals, operation <- ~w(all any) do
        %{"op" => operation, "args" => [%{"op" => "not", "arg" => left}, right]}
      end

    comparisons =
      for operator <- ~w(eq lt gt), expected <- [1000, 2500, 3000] do
        %{"op" => operator, "binding" => "sensor", "value" => expected}
      end

    nested =
      for comparison <- comparisons do
        %{
          "op" => "all",
          "args" => [
            %{"op" => "not", "arg" => %{"op" => "literal", "value" => false}},
            %{"op" => "any", "args" => [comparison, %{"op" => "literal", "value" => "unknown"}]}
          ]
        }
      end

    for predicate <- Enum.concat([literals, combinations, comparisons, nested]),
        value <- [1000, 2500, 3000, nil] do
      source = %{@source | "condition" => predicate}

      assert {:ok, program} =
               Compiler.compile(source, context.context, context.profile, context.limits)

      snapshot = %{context.snapshot | "active_programs" => [program.data["ir_digest"]]}

      snapshot =
        if value == nil,
          do: put_in(snapshot, ["facts", "sensor"], nil),
          else: put_in(snapshot, ["facts", "sensor", "value"], value)

      expected = Wotex.Routines.SourceTruthOracle.evaluate(predicate, %{"sensor" => value})

      assert Evaluation.evaluate(program, snapshot, context.time, context.profile, context.limits) ==
               {:ok, expected}
    end
  end

  defp evaluate(context, snapshot, time) do
    Evaluation.evaluate(context.program, snapshot, time, context.profile, context.limits)
  end
end
