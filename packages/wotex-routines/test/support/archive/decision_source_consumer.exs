Code.require_file("decision_inputs.exs", __DIR__)
Code.require_file("decision_source_oracle.exs", __DIR__)

defmodule DecisionSourceConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias DecisionArchiveInputs, as: Input
  alias DecisionSourceOracle, as: Oracle
  alias Wotex.Routines.{Collection, Decision, Edge, Error, Limits, Model, Profile, Run, Transition}

  setup_all do
    Input.base()
  end

  test "raw source derives full point and retained motion under both time grammars", base do
    child = Input.compile(base, "child", condition: Input.literal(false)).source

    forms = [
      %{"id" => "noop", "kind" => "noop"},
      Input.effect(),
      %{
        "id" => "sequence",
        "kind" => "sequence",
        "steps" => [%{"id" => "noop", "kind" => "noop"}, Input.effect()]
      },
      %{"id" => "wait", "kind" => "wait", "condition" => Input.literal(false), "timeout_ms" => 7},
      %{
        "id" => "all",
        "kind" => "parallel",
        "branches" => [Input.effect("a"), Input.effect("b", true)]
      },
      %{
        "id" => "choice",
        "kind" => "if",
        "condition" => Input.literal(true),
        "then" => Input.effect(),
        "else" => %{"id" => "noop", "kind" => "noop"}
      },
      %{
        "id" => "choice",
        "kind" => "if",
        "condition" => Input.literal("unknown"),
        "then" => Input.effect(),
        "else" => %{"id" => "noop", "kind" => "noop"}
      },
      %{
        "id" => "call",
        "kind" => "invoke",
        "routine_id" => "child",
        "revision" => "1",
        "arguments" => %{}
      }
    ]

    for grammar <- [1, 2], {steps, index} <- Enum.with_index(forms) do
      selected =
        if grammar == 1,
          do: %{base | time: Map.drop(base.time, ~w(format utc_generation))},
          else: base

      c = Input.compile(selected, "source:#{grammar}:#{index}", steps: steps, definitions: [child])
      expected = Oracle.advance(c)
      result = Input.point(c)
      assert result === expected
      assert :ok == verify(c, Input.prior(), result)
      wrong = put_in(result, ["basis", "time", "elapsed_ms"], c.time["elapsed_ms"] + 1)
      assert {:error, %Error{code: :invalid_transition}} = verify(c, Input.prior(), wrong)
    end

    c = Input.compile(base, "source:retained", steps: Input.delay(5))
    expected = Oracle.advance(c)
    initial = Input.point(c)
    assert initial === expected
    resumed = %{c | event: Input.event(c, "resume"), time: %{c.time | "elapsed_ms" => 25}}
    expected_next = Oracle.advance(resumed, expected["run"])
    actual = Input.point(resumed, initial["run"])
    assert actual === expected_next
    assert :ok == verify(resumed, Input.prior(initial["run"]), actual)
    wrong = put_in(actual, ["run", "steps", Access.at(0), "started_ms"], 21)

    assert {:error, %Error{code: :invalid_transition}} =
             verify(resumed, Input.prior(initial["run"]), wrong)
  end

  test "receipt history preserves charges and cannot conceal old deadlines or dependent paths",
       base do
    c = Input.compile(base, "source:receipts", run_ms: 20_000)
    expected = Oracle.advance(c)
    first = Input.point(c)
    assert first === expected

    admit = %{
      c
      | event:
          Input.event(c, "admission", %{"path" => [], "ref" => "charge:source", "outcome" => "held"})
    }

    expected_held = Oracle.receipt_run(admit, expected["run"], "admission", "reserved")
    held = Input.point(admit, first["run"])
    assert held === Oracle.result(admit, expected["run"], expected_held, [])
    assert :ok == verify(admit, Input.prior(first["run"]), held)
    repeated = Input.point(admit, held["run"])
    assert repeated === Oracle.result(admit, expected_held, expected_held, [])
    assert :ok == verify(admit, Input.prior(held["run"]), repeated)

    cancelled_c = %{c | event: Input.event(c, "cancel")}
    cancelled = Input.point(cancelled_c, held["run"])

    assert cancelled ===
             Oracle.result(
               cancelled_c,
               expected_held,
               Oracle.stopped(cancelled_c, expected_held, "cancelled", "cancelled"),
               []
             )

    assert :ok == verify(cancelled_c, Input.prior(held["run"]), cancelled)

    match = Input.matching(c)

    match = %{
      match
      | event:
          Input.event(match, "satisfied", %{
            "path" => [],
            "ref" => "match:source",
            "fact_id" => "output:current",
            "report_contract" => Enum.at(c.context["bases"], 2)["evidence"]["report_contract"]
          })
    }

    matched = Input.point(match, held["run"])
    expected_matched = Oracle.satisfied(match, expected_held)
    assert matched === expected_matched
    assert :ok == verify(match, Input.prior(held["run"]), matched)

    refunded =
      matched
      |> put_in(["run", "steps", Access.at(0), "receipts", "admission"], nil)
      |> put_in(["run", "spent"], [])

    assert {:ok, _} = Run.new(refunded["run"], c.program, c.profile, c.limits)

    assert {:error, %Error{code: :invalid_transition}} =
             verify(match, Input.prior(held["run"]), refunded)

    restored = JSON.decode!(JSON.encode!(matched["run"]))

    duplicate = %{
      match
      | snapshot: put_in(match.snapshot, ["facts", "output"], nil),
        time: %{match.time | "elapsed_ms" => 40_000}
    }

    replay = Input.point(duplicate, restored)
    assert replay === Oracle.result(duplicate, expected_matched["run"], expected_matched["run"], [])
    assert :ok == verify(duplicate, Input.prior(restored), replay)

    send_c = %{c | event: Input.event(c, "handoff", %{"path" => [], "ref" => "handoff:source"})}
    sent = Input.point(send_c, held["run"])
    expected_sent = Oracle.receipt_run(send_c, expected_held, "handoff", "handed_off")
    assert sent === Oracle.result(send_c, expected_held, expected_sent, [])

    for outcome <- ~w(failed unknown) do
      report = %{
        c
        | event:
            Input.event(c, "result", %{
              "path" => [],
              "ref" => "result:source",
              "stage" => "protocol_response",
              "outcome" => outcome,
              "report_contract" => nil
            })
      }

      result = Input.point(report, sent["run"])
      run = Oracle.receipt_run(report, expected_sent, "protocol_response", outcome)

      run =
        put_in(run, ["steps", Access.at(0), "receipts", "terminal"], Oracle.receipt(report.event))

      run = %{
        run
        | "status" => if(outcome == "failed", do: "partial", else: "unknown"),
          "reason" => if(outcome == "failed", do: "effect_failed", else: "effect_unknown")
      }

      assert result === Oracle.result(report, expected_sent, run, [])
      assert :ok == verify(report, Input.prior(sent["run"]), result)
    end

    sequence = %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [Input.effect("first"), Input.effect("dependent", true)]
    }

    seq = Input.compile(base, "source:late", steps: sequence, run_ms: 20_000)
    first = Input.point(seq)
    own = Oracle.advance(seq)
    assert first === own

    admit = %{
      seq
      | event:
          Input.event(seq, "admission", %{
            "path" => [0],
            "ref" => "charge:late",
            "outcome" => "held"
          })
    }

    held = Input.point(admit, first["run"])
    own_held = Oracle.receipt_run(admit, own["run"], "admission", "reserved")
    assert held === Oracle.result(admit, own["run"], own_held, [])
    send_c = %{seq | event: Input.event(seq, "handoff", %{"path" => [0], "ref" => "handoff:late"})}
    sent = Input.point(send_c, held["run"])
    own_sent = Oracle.receipt_run(send_c, own_held, "handoff", "handed_off")
    assert sent === Oracle.result(send_c, own_held, own_sent, [])
    deadline = Enum.at(own_sent["steps"], 1)["deadline_ms"]

    late = %{
      seq
      | event:
          Input.event(seq, "result", %{
            "path" => [0],
            "ref" => "report:late",
            "stage" => "reported_match",
            "outcome" => "accepted",
            "report_contract" => Enum.at(seq.context["bases"], 2)["evidence"]["report_contract"]
          }),
        time: %{seq.time | "elapsed_ms" => deadline}
    }

    result = Input.point(late, sent["run"])
    own_late = Oracle.receipt_run(late, own_sent, "reported_match", "completed")
    own_late = Oracle.stopped(late, own_late, "expired", "deadline_elapsed")
    assert result === Oracle.result(late, own_sent, own_late, [])
    assert Enum.at(result["run"]["steps"], 2)["status"] == "cancelled"
    assert :ok == verify(late, Input.prior(sent["run"]), result)

    child = Input.compile(base, "deadline:child", condition: Input.literal(false), run_ms: 7).source

    call = %{
      "id" => "call",
      "kind" => "invoke",
      "routine_id" => "deadline:child",
      "revision" => "1",
      "arguments" => %{}
    }

    invoking =
      Input.compile(base, "source:invoke:deadline",
        steps: call,
        definitions: [child],
        run_ms: 20_000
      )

    initial = Input.point(invoking)
    own = Oracle.advance(invoking)
    assert initial === own

    expired = %{
      invoking
      | event: Input.event(invoking, "resume"),
        time: %{invoking.time | "elapsed_ms" => 27}
    }

    actual = Input.point(expired, initial["run"])
    expected = Oracle.stopped(expired, own["run"], "expired", "deadline_elapsed")
    assert actual === Oracle.result(expired, own["run"], expected, [])
    assert :ok == verify(expired, Input.prior(initial["run"]), actual)
  end

  test "raw samples establish an edge baseline without inventing first or reconnected eligibility",
       base do
    trigger = %{
      "kind" => "edge",
      "binding" => "measurement",
      "direction" => "rising",
      "debounce_ms" => 0,
      "cooldown_ms" => 20,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    for grammar <- [1, 2] do
      selected =
        if grammar == 1,
          do: %{base | time: Map.drop(base.time, ~w(format utc_generation))},
          else: base

      c = Input.compile(selected, "source:edge:#{grammar}", sensor: true, trigger: trigger)
      low = Input.sample(c, 1, 1000, 20)
      first = Input.point(low)
      expected = edge_baseline(low, false)
      assert first["edge"] === expected
      assert first["run"] == nil and first["proposals"] == [] and first["outcome"] == "no-edge"
      assert :ok == verify(low, Input.prior(), first)
      wrong = put_in(first, ["edge", "baseline"], true)
      assert {:ok, _} = Edge.new(wrong["edge"], c.program, c.profile, c.limits)
      assert {:error, %Error{code: :invalid_transition}} = verify(low, Input.prior(), wrong)

      high = Input.sample(c, 2, 3000, 30)
      rising = Input.point(high, nil, first["edge"])

      expected_edge =
        edge_baseline(high, true)
        |> Map.put("cooldown_until_ms", 50)
        |> Map.put("last_original", high.event["original"])

      expected_point =
        Oracle.advance(high)
        |> Map.put("edge", expected_edge)
        |> put_in(["basis", "prior", "edge"], expected)

      assert rising === expected_point
      assert :ok == verify(high, Input.prior(nil, first["edge"]), rising)

      reconnected =
        high
        |> put_in(
          [:snapshot, "binding_bases", "measurement", "source_epoch"],
          "connection:replaced"
        )
        |> put_in([:snapshot, "facts", "measurement", "source_epoch"], "connection:replaced")

      reset = Input.point(reconnected, nil, first["edge"])
      assert reset["edge"] === edge_baseline(reconnected, true)
      assert reset["outcome"] == "no-edge" and reset["proposals"] == []
      assert :ok == verify(reconnected, Input.prior(nil, first["edge"]), reset)

      stale = put_in(low, [:snapshot, "facts", "measurement", "quality"], "stale")
      unqualified = Input.point(stale)

      expected =
        edge_baseline(stale, nil)
        |> Map.merge(
          Map.new(~w(last_receipt_ms last_sequence last_fact_id last_fact_digest), &{&1, nil})
        )

      assert unqualified["edge"] === expected
      assert unqualified["outcome"] == "no-edge" and unqualified["run"] == nil
      assert :ok == verify(stale, Input.prior(), unqualified)
    end
  end

  test "raw negative membership bounds the whole current cut and retains its original delayed start",
       base do
    members = [
      Input.compile(base, "source:delayed", steps: Input.delay(5)),
      Input.compile(base, "source:ready", steps: Input.effect("ready", true))
    ]

    input = Input.input(base, members)
    collection = Input.collection(base, input)
    expected = source_results(members, input)
    assert collection.data["transitions"] === expected
    assert length(collection.data["proposals"]) == 1
    assert :ok == Decision.verify_point(input, collection, base.profile, base.limits)
    decision = Input.decision(base, collection)
    assert decision.data["cell"]["elapsed"] == %{"min" => 20, "max" => 24}
    assert decision.data["cell"]["utc_mode"] == "ignored"
    current = Input.current(base, collection)

    assert {:ok, checked} =
             Decision.check(
               decision,
               put_in(current, ["input", "time", "elapsed_ms"], 24),
               base.profile,
               base.limits
             )

    assert checked["transitions"] === expected

    assert {:error, %Error{code: :stale_decision_time}} =
             Decision.check(
               decision,
               put_in(current, ["input", "time", "elapsed_ms"], 25),
               base.profile,
               base.limits
             )

    assert :ok == Decision.verify_point(input, collection, base.profile, base.limits)

    for boundary <- [23, 25] do
      wrong =
        decision.data
        |> put_in(["cell", "elapsed", "max"], boundary)
        |> Input.rehash("decision_digest")

      assert {:error, %Error{code: :invalid_collection_decision}} =
               Decision.to_map(wrong, base.profile, base.limits)
    end

    delayed = hd(members).program.data["ir_digest"]

    missing =
      collection.data
      |> update_in(
        ["input", "entries"],
        &Enum.reject(&1, fn entry -> entry["program"]["ir_digest"] == delayed end)
      )
      |> update_in(
        ["transitions"],
        &Enum.reject(&1, fn entry -> entry["program_digest"] == delayed end)
      )
      |> Input.rehash("collection_digest")

    assert {:error, %Error{code: :invalid_collection_decision}} =
             Decision.verify_point(input, missing, base.profile, base.limits)

    assert {:error, %Error{code: :invalid_collection_decision}} =
             Decision.new(missing, base.profile, base.limits)

    next = put_in(Input.retained(collection), ["time", "elapsed_ms"], 25)
    fresh = Input.collection(base, next)
    own_before = Map.new(expected, &{&1["program_digest"], &1["result"]["run"]})
    assert fresh.data["transitions"] === source_results(members, next, own_before)
    assert Enum.all?(fresh.data["transitions"], &(&1["result"]["run"]["start_ms"] == 20))
    fresh_decision = Input.decision(base, fresh)
    fresh_current = Input.current(base, fresh)
    assert Enum.all?(fresh_current["arbitration"]["decisions"], &(&1["outcome"] == "conflict"))
    assert {:ok, checked} = Decision.check(fresh_decision, fresh_current, base.profile, base.limits)
    assert checked["transitions"] === fresh.data["transitions"]
    assert checked["point_time"] === next["time"]

    waiting =
      Input.compile(base, "source:negative:wait",
        steps: %{
          "id" => "wait",
          "kind" => "wait",
          "condition" => Input.literal(false),
          "timeout_ms" => 3
        }
      )

    sampled =
      Input.compile(base, "source:negative:fact", sensor: true, condition: Input.literal(false))
      |> Input.sample(1, 3000, 20)

    sampled = %{
      sampled
      | event: Input.event(sampled, "manual"),
        snapshot: put_in(sampled.snapshot, ["facts", "measurement", "expires_ms"], 24)
    }

    for {negative, boundary} <- [{waiting, 23}, {sampled, 24}] do
      cut = Input.input(base, [negative, List.last(members)])
      collection = Input.collection(base, cut)
      assert collection.data["transitions"] === source_results([negative, List.last(members)], cut)
      decision = Input.decision(base, collection)
      assert decision.data["cell"]["elapsed"] == %{"min" => 20, "max" => boundary - 1}
      current = Input.current(base, collection)

      assert {:ok, _} =
               Decision.check(
                 decision,
                 put_in(current, ["input", "time", "elapsed_ms"], boundary - 1),
                 base.profile,
                 base.limits
               )

      assert {:error, %Error{code: :stale_decision_time}} =
               Decision.check(
                 decision,
                 put_in(current, ["input", "time", "elapsed_ms"], boundary),
                 base.profile,
                 base.limits
               )
    end

    schedule = "sha256:" <> String.duplicate("6", 64)

    due =
      Input.compile(base, "source:negative:window",
        condition: Input.literal(false),
        trigger: %{"kind" => "due", "schedule_id" => "window", "schedule_basis" => schedule}
      )

    due = %{
      due
      | event:
          Input.event(due, "due", %{
            "schedule_id" => "window",
            "schedule_basis" => schedule,
            "due_ms" => base.time["utc_low_ms"],
            "late_window_ms" => 5,
            "clock_generation" => base.time["utc_generation"],
            "time_zone_basis" => schedule
          })
    }

    cut = Input.input(base, [due, List.last(members)])
    collection = Input.collection(base, cut)
    assert collection.data["transitions"] === source_results([due, List.last(members)], cut)
    decision = Input.decision(base, collection)
    assert decision.data["cell"]["utc_high"]["max"] == base.time["utc_high_ms"] + 4
    current = Input.current(base, collection)

    assert {:ok, _} =
             Decision.check(
               decision,
               put_in(current, ["input", "time", "utc_high_ms"], base.time["utc_high_ms"] + 4),
               base.profile,
               base.limits
             )

    assert {:error, %Error{code: :stale_decision_time}} =
             Decision.check(
               decision,
               put_in(current, ["input", "time", "utc_high_ms"], base.time["utc_high_ms"] + 5),
               base.profile,
               base.limits
             )
  end

  test "raw complete contributors and all-pairs conflicts precede the selected cutoff", base do
    members = [
      Input.compile(base, "source:equiv:a"),
      Input.compile(base, "source:equiv:b"),
      Input.compile(base, "source:incompatible", steps: Input.effect("other", true)),
      Input.compile(base, "source:independent", target: "other")
    ]

    input = Input.input(base, members)
    first = Input.collection(base, input)
    raw = source_results(members, input) |> Enum.flat_map(& &1["result"]["proposals"])
    assert first.data["proposals"] === raw
    next = Input.retained(first)
    entry = hd(next["entries"])

    admission =
      Map.merge(entry["event"], %{
        "kind" => "admission",
        "path" => [],
        "ref" => "charge:contributor",
        "outcome" => "held"
      })

    held = Input.collection(base, put_in(next, ["entries", Access.at(0), "event"], admission))
    assert held.data["proposals"] === raw
    assert Enum.count(held.data["proposal_states"], &(&1["status"] == "reserved")) == 1
    assert Enum.all?(held.data["transitions"], &(&1["result"]["proposals"] == []))
    decision = Input.decision(base, held)

    allowed =
      Map.new(raw, &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}})

    same =
      Enum.find(raw, &(&1["thing_id"] == "urn:archive:shared" and &1["input"] == false))[
        "step_original"
      ]

    contrary = Enum.find(raw, & &1["input"])["step_original"]

    policies = [
      allowed,
      put_in(allowed, [same, "override"], "selected"),
      allowed
      |> put_in([same, "override"], "selected")
      |> put_in([contrary, "override"], "selected"),
      put_in(allowed, [contrary, "constraint"], "unknown"),
      put_in(allowed, [same, "constraint"], "refused"),
      put_in(allowed, [contrary, "override"], "suppressed")
    ]

    for ds <- policies, batch <- [1, 2] do
      current = Input.current(base, held, batch, ds)
      expected = Oracle.arbitrate(raw, ds, batch, held.data["collection_digest"])
      assert current["arbitration"] === expected
      assert {:ok, checked} = Decision.check(decision, current, base.profile, base.limits)
      assert checked["arbitration"] === expected
      assert checked["transitions"] === held.data["transitions"]
    end

    missing =
      held.data
      |> update_in(["proposals"], &tl/1)
      |> update_in(["proposal_states"], &tl/1)
      |> Input.rehash("collection_digest")

    assert {:error, %Error{code: :invalid_collection_decision}} =
             Decision.new(missing, base.profile, base.limits)

    many = capacity_members(base)
    input = Input.input(base, many)
    collection = Input.collection(base, input)
    raw = source_results(many, input) |> Enum.flat_map(& &1["result"]["proposals"])
    assert collection.data["proposals"] === raw
    assert length(raw) == 1024
    assert length(collection.data["proposal_states"]) == 1024
    current = Input.current(base, collection, 16)

    expected =
      Oracle.arbitrate(raw, current["dispositions"], 16, collection.data["collection_digest"])

    assert current["arbitration"] === expected
    assert length(expected["selected"]) == 16
    assert Enum.count(expected["decisions"], &(&1["outcome"] == "conflict")) == 32
    assert Enum.count(expected["decisions"], &(&1["outcome"] == "batch-deferred")) == 736
    decision = Input.decision(base, collection)
    assert {:ok, checked} = Decision.check(decision, current, base.profile, base.limits)
    assert checked["arbitration"] === expected
    {:ok, profile} = Profile.new(%{base.profile.data | "pending_work" => 1023})
    narrow = %{base | profile: profile}
    candidate = Input.claimed(narrow, Input.input(narrow, capacity_members(narrow)))

    assert {:error, %Error{code: :pending_work_bound}} =
             Decision.new(candidate, profile, base.limits)
  end

  test "raw Fact time thresholds constrain both UTC endpoints and exact current inputs", base do
    c = Input.compile(base, "source:utc", sensor: true, source_time: true)
    sampled = Input.sample(c, 1, 3000, 20)
    c = %{sampled | event: c.event}
    input = Input.input(base, [c])
    collection = Input.collection(base, input)
    assert collection.data["transitions"] === source_results([c], input)
    decision = Input.decision(base, collection)
    fact = c.snapshot["facts"]["measurement"]
    sensor = hd(c.context["bases"])
    {:ok, instant, _} = DateTime.from_iso8601(fact["source_time"])
    center = DateTime.to_unix(instant, :millisecond)
    earliest = center + fact["source_uncertainty_ms"]
    latest = center - fact["source_uncertainty_ms"] + sensor["evidence"]["freshness_ms"]
    assert decision.data["cell"]["utc_mode"] == "present"
    assert decision.data["cell"]["utc_low"]["min"] == earliest
    assert decision.data["cell"]["utc_high"]["max"] == latest
    current = Input.current(base, collection)

    for {low, high} <- [
          {earliest, latest},
          {center + 400, center + 600},
          {center + 600, center + 700},
          {center + 300, center + 400}
        ] do
      changed =
        current
        |> put_in(["input", "time", "utc_low_ms"], low)
        |> put_in(["input", "time", "utc_high_ms"], high)

      assert {:ok, checked} = Decision.check(decision, changed, base.profile, base.limits)
      assert checked["point_time"] === base.time
      assert checked["checked_time"] === changed["input"]["time"]
      assert checked["transitions"] === collection.data["transitions"]
    end

    for time <- [
          %{base.time | "utc_low_ms" => earliest - 1},
          %{base.time | "utc_high_ms" => latest + 1},
          %{base.time | "utc_generation" => "utc:replaced"},
          %{base.time | "utc_low_ms" => nil, "utc_high_ms" => nil, "utc_generation" => nil},
          %{base.time | "epoch" => "other"},
          %{base.time | "clock_generation" => "other"},
          %{base.time | "elapsed_ms" => 19},
          Map.drop(base.time, ~w(format utc_generation))
        ] do
      assert {:error, %Error{code: :stale_decision_time}} =
               Decision.check(
                 decision,
                 put_in(current, ["input", "time"], time),
                 base.profile,
                 base.limits
               )
    end

    changed =
      current
      |> put_in(["input", "membership", "generation"], "different")
      |> put_in(["input", "time", "elapsed_ms"], 0)

    assert {:error, %Error{code: :stale_decision_input}} =
             Decision.check(decision, changed, base.profile, base.limits)

    c = Input.compile(base, "source:elapsed")
    collection = Input.collection(base, Input.input(base, [c]))
    decision = Input.decision(base, collection)
    current = Input.current(base, collection)
    assert decision.data["cell"]["utc_mode"] == "ignored"

    for time <- [
          %{base.time | "utc_generation" => "utc:changed"},
          %{base.time | "utc_generation" => nil, "utc_low_ms" => nil, "utc_high_ms" => nil}
        ] do
      assert {:ok, _} =
               Decision.check(
                 decision,
                 put_in(current, ["input", "time"], time),
                 base.profile,
                 base.limits
               )
    end
  end

  test "public closed shapes, exact aggregate byte bounds and frozen model scope remain enforced",
       base do
    c = Input.compile(base, "source:closed")
    input = Input.input(base, [c])
    collection = Input.collection(base, input)
    decision = Input.decision(base, collection)

    for value <- [
          Map.put(decision, :extra, true),
          self(),
          [nil | :improper],
          Map.put(decision.data, "authorized", true)
        ] do
      assert {:error, %Error{}} = Decision.to_map(value, base.profile, base.limits)
    end

    for key <- Map.keys(decision.data) do
      assert {:error, %Error{}} =
               Decision.to_map(Map.delete(decision.data, key), base.profile, base.limits)
    end

    {:ok, legacy} = Collection.evaluate(Map.delete(input, "format"), base.profile, base.limits)

    assert {:error, %Error{code: :unsupported_decision_scope}} =
             Decision.new(legacy, base.profile, base.limits)

    scope =
      :wotex_routines
      |> :code.priv_dir()
      |> to_string()
      |> Path.join("vectors/wro-04-receipt-prefix.json")
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("scope")

    assert {:error, %Error{code: :unsupported_model_scope}} =
             Model.compile(
               c.program,
               %{scope | "environment" => "manual_receipts_complete_pending_arbitration"},
               base.profile,
               base.limits
             )

    for operation <- [:point, :new, :map, :check] do
      maximum =
        Enum.reduce_while(1..5, 1_000_000, fn _, candidate ->
          {c, collection, decision, current} = byte_fixture(base, candidate, operation)
          args = byte_arguments(c, collection, decision, current, operation)
          output = if operation == :new, do: json_size(decision.data), else: 0
          needed = max(json_size(args), output)
          if needed == candidate, do: {:halt, needed}, else: {:cont, needed}
        end)

      result = byte_call(byte_fixture(base, maximum, operation), operation)
      assert result == :ok or match?({:ok, _}, result)

      assert {:error, %Error{code: :limit_or_json_error}} =
               byte_call(byte_fixture(base, maximum - 1, operation, false), operation)
    end
  end

  defp capacity_members(base) do
    Enum.map(1..64, fn index ->
      value = index == 64
      target = if value, do: "capacity:1", else: "capacity:#{index}"

      steps = %{
        "id" => "all",
        "kind" => "parallel",
        "branches" =>
          Enum.map(0..3, fn group ->
            %{
              "id" => "group:#{group}",
              "kind" => "parallel",
              "branches" => Enum.map(0..3, &Input.effect("effect:#{group}:#{&1}", value))
            }
          end)
      }

      Input.compile(base, "source:capacity:#{index}", steps: steps, target: target)
    end)
  end

  defp byte_fixture(base, maximum, operation, measuring \\ true) do
    {:ok, limits} = Limits.new(%{base.limits.data | "max_bytes" => maximum})
    c = %{base | limits: limits}
    member = Input.compile(c, "source:bytes")
    collection = Input.collection(c, Input.input(c, [member]))

    decision =
      if operation in [:map, :check] or (operation == :new and measuring),
        do: Input.decision(c, collection)

    current = if operation == :check, do: Input.current(c, collection)
    {c, collection, decision, current}
  end

  defp byte_arguments(c, collection, decision, current, operation) do
    args =
      case operation do
        :point -> %{"input" => collection.data["input"], "collection" => collection.data}
        :new -> %{"collection" => collection.data}
        :map -> %{"decision" => decision.data}
        :check -> %{"decision" => decision.data, "context" => current}
      end

    Map.merge(args, %{"profile" => c.profile.data, "json_limits" => c.limits.data})
  end

  defp byte_call({c, collection, decision, current}, operation) do
    case operation do
      :point -> Decision.verify_point(collection.data["input"], collection, c.profile, c.limits)
      :new -> Decision.new(collection, c.profile, c.limits)
      :map -> Decision.to_map(decision, c.profile, c.limits)
      :check -> Decision.check(decision, current, c.profile, c.limits)
    end
  end

  defp json_size(data) do
    {:ok, bytes} =
      Wotex.JSON.encode(data,
        max_bytes: 67_108_864,
        max_depth: 64,
        max_nodes: 2_000_000,
        max_collection_size: 8192,
        max_string_bytes: 65_536
      )

    byte_size(bytes)
  end

  defp source_results(members, input, previous \\ %{}) do
    raw = Map.new(members, &{&1.program.data["ir_digest"], &1})

    input["entries"]
    |> Enum.map(fn entry ->
      id = entry["program"]["ir_digest"]
      c = %{raw[id] | snapshot: entry["snapshot"], event: entry["event"], time: input["time"]}
      %{"program_digest" => id, "result" => Oracle.advance(c, previous[id])}
    end)
    |> Enum.sort_by(& &1["program_digest"])
  end

  defp edge_baseline(c, baseline) do
    fact = c.snapshot["facts"]["measurement"]

    edge = %{
      "format" => "wotex.routines.edge@1",
      "program_digest" => c.program.data["ir_digest"],
      "binding" => "measurement",
      "binding_basis" => c.snapshot["binding_bases"]["measurement"],
      "epoch" => c.time["epoch"],
      "clock_generation" => c.time["clock_generation"],
      "last_elapsed_ms" => c.time["elapsed_ms"],
      "last_receipt_ms" => fact["receipt_ms"],
      "last_sequence" => fact["sequence"],
      "last_fact_id" => fact["id"],
      "last_fact_digest" => Oracle.hash(fact),
      "baseline" => baseline,
      "candidate_since_ms" => nil,
      "cooldown_until_ms" => 0,
      "last_original" => nil
    }

    if c.time["format"] == "wotex.routines.time@2",
      do:
        Map.merge(edge, %{
          "format" => "wotex.routines.edge@2",
          "time_format" => "wotex.routines.time@2"
        }),
      else: edge
  end

  defp verify(c, prior, result),
    do:
      Transition.verify(c.program, c.event, c.snapshot, c.time, prior, result, c.profile, c.limits)
end
