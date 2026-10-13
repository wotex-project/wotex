defmodule Wotex.Routines.CorrespondenceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Compiler, Error, Kernel, Limits, Profile, SourceTransitionOracle}

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

    basis = Enum.at(corpus["bases"], 2)

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "process",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ["output", "sensor"],
      "trigger" => %{"kind" => "manual"},
      "condition" => literal(true),
      "steps" => effect("apply"),
      "overlap" => "reject",
      "run_ms" => 1000
    }

    context = %{
      "registry" => corpus["registry"],
      "bases" => corpus["bases"],
      "bindings" => %{
        "output" => %{
          "basis" => Map.take(basis, ~w(id version semantic_digest)),
          "thing_id" => "urn:cell:output",
          "resource_roles" => %{"target" => "cell:1"}
        },
        "sensor" => %{
          "basis" => Map.take(hd(corpus["bases"]), ~w(id version semantic_digest)),
          "thing_id" => corpus["fact"]["thing_id"],
          "resource_roles" => %{}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" =>
        System.get_env("WOTEX_ROUTINES_COMPILER_BASIS") ||
          "sha256:" <> String.duplicate("7", 64)
    }

    %{
      corpus: corpus,
      basis: basis,
      source: source,
      context: context,
      limits: limits,
      profile: profile
    }
  end

  test "staged sequence, duplicates and skipped stages agree with the source reference", c do
    c = prepare(c, sequence([effect("first"), effect("second")]))

    trace(c, [
      tick(),
      admission([0]),
      admission([0]),
      handoff([0]),
      result([0], "local_queue"),
      result([0], "protocol_response"),
      result([0], "reported_match"),
      admission([1]),
      handoff([1]),
      result([1], "reported_match"),
      tick()
    ])
  end

  test "parallel result orders retain all branches and held roots", c do
    for order <- [[0, 1], [1, 0]], outcome <- ~w(accepted failed unknown) do
      c =
        prepare(c, %{
          "id" => "fork",
          "kind" => "parallel",
          "branches" => [effect("left"), effect("right")]
        })

      [first, second] = order
      tail = if outcome == "accepted", do: [result([second], "reported_match")], else: [tick()]

      trace(
        c,
        [
          tick(),
          admission([first]),
          handoff([first]),
          admission([second]),
          handoff([second]),
          result([first], "protocol_response"),
          result([first], "reported_match", outcome)
        ] ++ tail
      )
    end
  end

  test "refusal and cancellation preserve unsent versus handed-off outcomes", c do
    c = prepare(c, sequence([effect("first"), effect("second")]))

    for prefix <- [[tick()], [tick(), admission([0])], [tick(), admission([0]), handoff([0])]] do
      trace(c, prefix ++ [%{kind: "cancel"}, tick()])
    end

    trace(c, [tick(), admission([0], "refused"), tick()])

    trace(c, [
      tick(),
      admission([0]),
      handoff([0]),
      %{kind: "cancel"},
      result([0], "reported_match"),
      tick()
    ])
  end

  test "root unknowns and nested conditions never become an effect or false branch", c do
    predicate = %{"op" => "not", "arg" => %{"op" => "eq", "binding" => "sensor", "value" => 2000}}

    for condition <- [literal(false), literal("unknown"), predicate] do
      c = prepare(%{c | source: %{c.source | "condition" => condition}}, effect("apply"))
      trace(c, [tick(), tick(30)])
    end

    for condition <- [literal(true), literal(false), literal("unknown")] do
      c =
        prepare(c, %{
          "id" => "choice",
          "kind" => "if",
          "condition" => condition,
          "then" => effect("yes"),
          "else" => effect("no")
        })

      trace(c, [tick(), tick(30)])
    end
  end

  test "wait and delay boundaries, clock changes and root deadline agree", c do
    for predicate <- [literal(true), literal(false), literal("unknown")] do
      c =
        prepare(
          c,
          sequence([
            %{"id" => "wait", "kind" => "wait", "condition" => predicate, "timeout_ms" => 100},
            effect("after")
          ])
        )

      trace(c, [tick(), tick(119), tick(120), tick(121)])
    end

    c =
      prepare(
        c,
        sequence([%{"id" => "pause", "kind" => "delay", "duration_ms" => 100}, effect("after")])
      )

    trace(c, [tick(), tick(119), tick(120)])

    for finish <- [%{now: 19}, %{now: 1020}, %{epoch: "boot:2"}, %{generation: "clock:2"}] do
      trace(c, [tick(), finish])
    end

    c = prepare(c, effect("apply"))
    trace(c, [tick(), admission([]), handoff([]), tick(1020)])
  end

  test "changing observations preserve a chosen branch and recheck the root gate", c do
    predicate = %{"op" => "gt", "binding" => "sensor", "value" => 2000}

    branch = %{
      "id" => "choice",
      "kind" => "if",
      "condition" => predicate,
      "then" =>
        sequence([%{"id" => "pause", "kind" => "delay", "duration_ms" => 100}, effect("yes")]),
      "else" => effect("no")
    }

    c = prepare(c, branch)
    trace(c, [%{sensor: 2500}, %{sensor: 1000, now: 120}])
    c = prepare(%{c | source: %{c.source | "condition" => predicate}}, branch)
    trace(c, [%{sensor: 2500}, %{sensor: 1000, now: 120}, %{now: 121}, %{sensor: 2500, now: 122}])
    waiting = %{"id" => "wait", "kind" => "wait", "condition" => predicate, "timeout_ms" => 100}

    c =
      prepare(
        %{c | source: %{c.source | "condition" => literal(true)}},
        sequence([waiting, effect("after")])
      )

    trace(c, [tick(), %{sensor: 1000, now: 50}, %{sensor: 2500, now: 119}])
  end

  test "nested paths and finite elapsed sweeps agree at both deadline boundaries", c do
    for duration <- [1, 7, 100], offset <- [-1, 0, 1] do
      steps =
        sequence([
          %{"id" => "pause", "kind" => "delay", "duration_ms" => duration},
          %{
            "id" => "fork",
            "kind" => "parallel",
            "branches" => [
              Map.put(
                sequence([%{"id" => "noop", "kind" => "noop"}, effect("left")]),
                "id",
                "nested-sequence"
              ),
              effect("right")
            ]
          }
        ])

      c = prepare(c, steps)
      trace(c, [tick(), tick(20 + duration + offset)])
    end

    c = prepare(c, effect("apply"))

    for offset <- [-1, 0, 1] do
      trace(c, [tick(), tick(20 + min(1000, c.basis["timing"]["deadline_ms"]) + offset)])
    end
  end

  test "pinned child condition and inherited duration remain visible", c do
    for truth <- [true, false, "unknown"] do
      child = %{
        c.source
        | "id" => "child",
          "condition" => literal(truth),
          "run_ms" => 100,
          "steps" =>
            sequence([
              %{"id" => "delay", "kind" => "delay", "duration_ms" => 90},
              effect("child-effect")
            ])
      }

      c = %{c | context: %{c.context | "definitions" => [child]}}

      c =
        prepare(c, %{
          "id" => "call",
          "kind" => "invoke",
          "routine_id" => "child",
          "revision" => "1",
          "arguments" => %{}
        })

      trace(c, [tick(), tick(109), tick(110), tick(120)])
    end
  end

  test "definition removal halts future work and retains historical evidence", c do
    c = prepare(c, sequence([effect("first"), effect("second")]))

    trace(c, [
      tick(),
      admission([0]),
      handoff([0]),
      %{active: false},
      Map.put(result([0], "reported_match"), :active, false),
      %{active: false}
    ])
  end

  test "conflicting and out-of-order receipts agree on explicit refusal", c do
    c = prepare(c, effect("apply"))

    trace(c, [
      tick(),
      handoff([]),
      admission([]),
      Map.put(admission([]), :ref, "conflict"),
      result([], "reported_match"),
      handoff([]),
      result([], "reported_match"),
      result([], "protocol_response")
    ])
  end

  defp prepare(c, steps) do
    source = %{c.source | "steps" => steps}
    {:ok, program} = Compiler.compile(source, c.context, c.profile, c.limits)

    snapshot = %{
      "id" => "snapshot:1",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{
        "urn:cell:output" => 1,
        "cell:1" => 1,
        c.corpus["fact"]["thing_id"] => 1
      },
      "binding_bases" => %{
        "output" => %{
          "profile_digest" => c.basis["semantic_digest"],
          "source_id" => "output:1",
          "source_epoch" => "connection:1",
          "source_time_basis" => nil
        },
        "sensor" =>
          Map.take(c.corpus["fact"], ~w(profile_digest source_id source_epoch source_time_basis))
      },
      "facts" => %{"output" => nil, "sensor" => nil}
    }

    oracle =
      SourceTransitionOracle.new(source, c.context["definitions"], %{
        "output" => c.basis["timing"]["deadline_ms"]
      })

    Map.merge(c, %{program: program, snapshot: snapshot, oracle: oracle})
  end

  defp trace(c, frames) do
    Enum.reduce(frames, {nil, c.oracle}, fn frame, {run, oracle} ->
      event = event(c, frame)

      time = %{
        "epoch" => Map.get(frame, :epoch, "boot:1"),
        "clock_generation" => Map.get(frame, :generation, "clock:1"),
        "elapsed_ms" => Map.get(frame, :now, 20),
        "utc_low_ms" => nil,
        "utc_high_ms" => nil
      }

      active = Map.get(frame, :active, true)
      snapshot = if active, do: c.snapshot, else: %{c.snapshot | "active_programs" => []}
      {snapshot, time, values} = observation(c, frame, snapshot, time)
      expected = SourceTransitionOracle.advance(oracle, event, time, values, active)

      actual =
        Kernel.advance(
          c.program,
          event,
          snapshot,
          time,
          %{"original" => run, "busy" => nil, "edge" => nil},
          c.profile,
          c.limits
        )

      compare(expected, actual, run, oracle)
    end)
  end

  defp observation(c, %{sensor: value}, snapshot, time) do
    {:ok, date, _} = DateTime.from_iso8601(c.corpus["fact"]["source_time"])
    utc = DateTime.to_unix(date, :millisecond) + 500
    snapshot = put_in(snapshot, ["facts", "sensor"], %{c.corpus["fact"] | "value" => value})
    {snapshot, %{time | "utc_low_ms" => utc, "utc_high_ms" => utc}, %{"sensor" => value}}
  end

  defp observation(_, _, snapshot, time), do: {snapshot, time, %{}}

  defp compare({:error, code}, actual, run, oracle) do
    assert {:error, %Error{code: ^code}} = actual
    {run, oracle}
  end

  defp compare({:ok, oracle, proposals}, actual, prior, _) do
    assert {:ok, transition} = actual
    assert runtime_view(transition) == SourceTransitionOracle.view(oracle, proposals)
    run = transition["run"]
    originals = Enum.map(run["steps"], & &1["original"])
    assert length(originals) == length(Enum.uniq(originals))
    if prior, do: assert(originals == Enum.map(prior["steps"], & &1["original"]))

    for proposal <- transition["proposals"] do
      assert proposal["original"] == run["original"]
      record = Enum.find(run["steps"], &(&1["path"] == proposal["path"]))
      assert proposal["step_original"] == record["original"]
    end

    {run, oracle}
  end

  defp runtime_view(transition) do
    run = transition["run"]

    steps =
      Enum.map(run["steps"], fn record ->
        receipts =
          Map.new(record["receipts"], fn {slot, value} ->
            {slot, if(value, do: Map.take(value, ~w(ref outcome)), else: nil)}
          end)

        record
        |> Map.delete("original")
        |> Map.put("receipts", receipts)
      end)

    spent =
      Enum.map(run["spent"], fn receipt ->
        record = Enum.find(run["steps"], &(&1["original"] == receipt["original"]))
        assert record != nil
        %{"path" => record["path"], "ref" => receipt["ref"]}
      end)

    %{
      "outcome" => transition["outcome"],
      "reason" => run["reason"],
      "steps" => steps,
      "spent" => spent,
      "proposals" =>
        Enum.map(transition["proposals"], &Map.take(&1, ~w(path binding input completion)))
    }
  end

  defp event(c, frame) do
    kind = Map.get(frame, :kind, "manual")

    event = %{
      "kind" => kind,
      "original" => "original:1",
      "program_digest" => c.program.data["ir_digest"]
    }

    if kind in ~w(admission handoff result) do
      event =
        Map.merge(event, %{
          "path" => frame.path,
          "ref" =>
            Map.get(
              frame,
              :ref,
              "ref:" <> kind <> inspect(frame.path) <> Map.get(frame, :stage, "")
            )
        })

      receipt_fields(c, event, frame)
    else
      event
    end
  end

  defp receipt_fields(_, %{"kind" => "handoff"} = event, _), do: event

  defp receipt_fields(_, %{"kind" => "admission"} = event, frame),
    do: Map.put(event, "outcome", frame.outcome)

  defp receipt_fields(c, event, frame),
    do:
      Map.merge(event, %{
        "outcome" => frame.outcome,
        "stage" => frame.stage,
        "report_contract" =>
          if(frame.stage in ~w(correlated_report reported_match),
            do: c.basis["evidence"]["report_contract"],
            else: nil
          )
      })

  defp tick(now \\ 20), do: %{now: now}
  defp admission(path, outcome \\ "held"), do: %{kind: "admission", path: path, outcome: outcome}
  defp handoff(path), do: %{kind: "handoff", path: path}

  defp result(path, stage, outcome \\ "accepted"),
    do: %{kind: "result", path: path, stage: stage, outcome: outcome}

  defp literal(value), do: %{"op" => "literal", "value" => value}

  defp effect(id),
    do: %{
      "id" => id,
      "kind" => "effect",
      "binding" => "output",
      "input" => false,
      "completion" => "reported_match"
    }

  defp sequence(children), do: %{"id" => "sequence", "kind" => "sequence", "steps" => children}
end
