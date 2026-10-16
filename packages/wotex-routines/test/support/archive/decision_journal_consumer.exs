Code.require_file("decision_inputs.exs", __DIR__)
Code.require_file("decision_journal_oracle.exs", __DIR__)

defmodule DecisionJournalConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias DecisionArchiveInputs, as: Input
  alias DecisionConsumerJournal, as: Journal
  alias Wotex.Routines.{Collection, Decision, Edge, Error, Limits, Model, Profile, Run, Transition}

  setup_all do
    Input.base()
  end

  test "scripted journal rows fix both time grammars, branch choices and retained starts", base do
    child = Input.compile(base, "journal:child", condition: Input.literal(false), run_ms: 11).source

    scripts = [
      {%{"id" => "nothing", "kind" => "noop"},
       %{status: "completed", rows: [{[], "noop", "completed", 20, 1020, nil}]}},
      {Input.effect(), effect_plan(20, "proposed", new: true)},
      {Input.delay(7), delayed_plan("waiting", nil, [])},
      {%{"id" => "await", "kind" => "wait", "condition" => Input.literal(false), "timeout_ms" => 9},
       %{status: "running", rows: [{[], "wait", "waiting", 20, 29, nil}]}},
      {%{
         "id" => "fork",
         "kind" => "parallel",
         "branches" => [Input.effect("left"), Input.effect("right", true)]
       },
       %{
         status: "running",
         rows: [
           {[], "parallel", "waiting", 20, 1020, nil},
           {[0], "effect", "proposed", 20, 1020, nil},
           {[1], "effect", "proposed", 20, 1020, nil}
         ],
         new: [{[0], false}, {[1], true}]
       }},
      {%{
         "id" => "choose",
         "kind" => "if",
         "condition" => Input.literal(false),
         "then" => Input.effect(),
         "else" => Input.effect("other", true)
       },
       %{
         status: "running",
         rows: [
           {[], "if", "waiting", 20, 1020, "else"},
           {[0], "effect", "unsent", nil, nil, nil},
           {[1], "effect", "proposed", 20, 1020, nil}
         ],
         new: [{[1], true}]
       }},
      {%{
         "id" => "choose",
         "kind" => "if",
         "condition" => Input.literal("unknown"),
         "then" => Input.effect(),
         "else" => Input.effect("other", true)
       },
       %{
         status: "blocked",
         reason: "condition_blocked",
         rows: [
           {[], "if", "unsent", 20, 1020, nil},
           {[0], "effect", "unsent", nil, nil, nil},
           {[1], "effect", "unsent", nil, nil, nil}
         ]
       }},
      {%{
         "id" => "nested",
         "kind" => "invoke",
         "routine_id" => "journal:child",
         "revision" => "1",
         "arguments" => %{}
       },
       %{
         status: "blocked",
         reason: "condition_blocked",
         rows: [{[], "invoke", "waiting", 20, 31, nil}, {[0], "effect", "unsent", nil, nil, nil}]
       }}
    ]

    for grammar <- [1, 2], {{steps, plan}, index} <- Enum.with_index(scripts) do
      selected =
        if grammar == 1,
          do: %{base | time: Map.drop(base.time, ~w(format utc_generation))},
          else: base

      c =
        Input.compile(selected, "journal:script:#{grammar}:#{index}",
          steps: steps,
          definitions: [child]
        )

      expected = Journal.point(c, Input.prior(), plan)
      result = Input.point(c)
      assert result === expected
      assert :ok == verify(c, Input.prior(), result)
      wrong = put_in(result, ["basis", "snapshot", "id"], "unowned")
      assert {:error, %Error{code: :invalid_transition}} = verify(c, Input.prior(), wrong)
    end

    c = Input.compile(base, "journal:latched", steps: Input.delay(7))
    input = Input.input(base, [c])
    expected_point = Journal.point(c, Input.prior(), delayed_plan("waiting", nil, []))
    expected = owned_collection(base, input, [expected_point], [])
    actual = Input.collection(base, input)
    assert actual.data === expected
    owner = Journal.open(input)
    {owner, capture} = Journal.capture(owner)
    assert {:ok, owner} = Journal.commit_inert(owner, capture, actual.data, expected)
    owner = Journal.tick(owner, %{base.time | "elapsed_ms" => 28})
    resumed = Journal.retained(owner)
    next = Input.collection(base, resumed)
    entry = hd(resumed["entries"])
    now = %{c | event: entry["event"], time: resumed["time"]}

    expected_point =
      Journal.point(now, entry["prior"], delayed_plan("completed", 28, [{[1], false}]))

    assert hd(next.data["transitions"])["result"] === expected_point
    assert expected_point["run"]["start_ms"] == 20
    wrong = put_in(expected_point, ["run", "steps", Access.at(0), "started_ms"], 21)
    assert {:error, %Error{code: :invalid_transition}} = verify(now, entry["prior"], wrong)
  end

  test "journal charge and receipt custody survives stops, restore and late evidence", base do
    c = Input.compile(base, "journal:charged", run_ms: 20_000)

    first_plan = %{
      effect_plan(20, "proposed", new: true)
      | rows: [{[], "effect", "proposed", 20, 15_020, nil}]
    }

    first = Input.point(c)
    first_reference = Journal.point(c, Input.prior(), first_plan)
    assert first === first_reference
    input = Input.input(base, [c])

    first_cut =
      owned_collection(base, input, [first_reference], [
        {Journal.proposal(c, [], false), "proposed"}
      ])

    owner = Journal.open(input)
    {owner, token} = Journal.capture(owner)
    assert {:ok, owner} = Journal.commit_inert(owner, token, first_cut, first_cut)
    {replay_owner, replay_token} = Journal.capture(owner)

    assert {:error, :stale_history} =
             Journal.commit_inert(replay_owner, replay_token, first_cut, first_cut)

    resumed = Journal.retained(owner)

    admission =
      Input.event(c, "admission", %{"path" => [], "ref" => "journal:charge", "outcome" => "held"})

    changed = put_in(resumed, ["entries", Access.at(0), "event"], admission)
    owner = Journal.replace(owner, changed)
    {owner, token} = Journal.capture(owner)
    held_c = %{c | event: admission}
    receipts = %{[] => %{"admission" => Journal.receipt(admission)}}

    held_plan = %{
      status: "running",
      rows: [{[], "effect", "reserved", 20, 15_020, nil}],
      receipts: receipts
    }

    expected_held = Journal.point(held_c, Input.prior(first_reference["run"]), held_plan)
    actual = Input.collection(base, changed)

    expected =
      owned_collection(base, changed, [expected_held], [
        {Journal.proposal(c, [], false), "reserved"}
      ])

    assert actual.data === expected
    stale = Journal.replace(owner, put_in(owner.input, ["membership", "generation"], "different"))
    assert {:error, :stale} = Journal.commit_inert(stale, token, actual.data, expected)
    assert {:ok, owner} = Journal.commit_inert(owner, token, actual.data, expected)
    assert owner.charges == [%{"original" => Journal.original(c, []), "ref" => "journal:charge"}]
    restored = Journal.restore(Journal.dump(owner))
    assert restored.charges === owner.charges and restored.references === owner.references

    repeated = Input.point(held_c, expected_held["run"])
    assert repeated === Journal.point(held_c, Input.prior(expected_held["run"]), held_plan)
    assert :ok == verify(held_c, Input.prior(expected_held["run"]), repeated)
    cancel_c = %{c | event: Input.event(c, "cancel")}
    cancelled = Input.point(cancel_c, expected_held["run"])

    cancel_plan =
      %{held_plan | status: "cancelled", rows: [{[], "effect", "cancelled", 20, 15_020, nil}]}
      |> Map.put(:reason, "cancelled")

    assert cancelled === Journal.point(cancel_c, Input.prior(expected_held["run"]), cancel_plan)
    assert :ok == verify(cancel_c, Input.prior(expected_held["run"]), cancelled)

    matched_c = Input.matching(c)

    matched_c = %{
      matched_c
      | event:
          Input.event(c, "satisfied", %{
            "path" => [],
            "ref" => "journal:match",
            "fact_id" => "output:current",
            "report_contract" => report_contract(c)
          })
    }

    matched_plan = %{
      held_plan
      | status: "completed",
        rows: [{[], "effect", "completed", 20, 15_020, nil}],
        receipts: %{[] => Map.put(receipts[[]], "satisfied", Journal.receipt(matched_c.event))}
    }

    matched = Input.point(matched_c, expected_held["run"])
    expected_match = Journal.point(matched_c, Input.prior(expected_held["run"]), matched_plan)
    assert matched === expected_match
    assert :ok == verify(matched_c, Input.prior(expected_held["run"]), matched)

    refunded =
      matched
      |> put_in(["run", "spent"], [])
      |> put_in(["run", "steps", Access.at(0), "receipts", "admission"], nil)

    assert {:ok, _} = Run.new(refunded["run"], c.program, c.profile, c.limits)

    assert {:error, %Error{code: :invalid_transition}} =
             verify(matched_c, Input.prior(expected_held["run"]), refunded)

    match_input =
      Journal.retained(restored)
      |> put_in(["entries", Access.at(0), "event"], matched_c.event)
      |> put_in(["entries", Access.at(0), "snapshot"], matched_c.snapshot)

    restored = Journal.replace(restored, match_input)
    {restored, token} = Journal.capture(restored)
    good_cut = owned_collection(base, match_input, [expected_match], [])
    bad_cut = put_in(good_cut, ["transitions", Access.at(0), "result"], refunded)
    assert {:error, :lost_charge} = Journal.commit_inert(restored, token, bad_cut, good_cut)
    assert {:ok, completed_owner} = Journal.commit_inert(restored, token, good_cut, good_cut)
    assert completed_owner.charges === owner.charges

    restored_completed = Journal.restore(Journal.dump(completed_owner))
    prior_completed = hd(restored_completed.references)["result"]["run"]

    late_match = %{
      matched_c
      | snapshot: put_in(matched_c.snapshot, ["facts", "output"], nil),
        time: %{matched_c.time | "elapsed_ms" => 40_000}
    }

    replay = Input.point(late_match, prior_completed)
    terminal_plan = Map.put(matched_plan, :last, 20)
    assert replay === Journal.point(late_match, Input.prior(expected_match["run"]), terminal_plan)
    assert :ok == verify(late_match, Input.prior(prior_completed), replay)
    assert replay["run"]["spent"] === restored_completed.charges

    send_c = %{c | event: Input.event(c, "handoff", %{"path" => [], "ref" => "journal:send"})}
    sent_receipts = %{[] => Map.put(receipts[[]], "handoff", Journal.receipt(send_c.event))}

    sent_plan = %{
      held_plan
      | rows: [{[], "effect", "handed_off", 20, 15_020, nil}],
        receipts: sent_receipts
    }

    sent = Input.point(send_c, expected_held["run"])
    own_sent = Journal.point(send_c, Input.prior(expected_held["run"]), sent_plan)
    assert sent === own_sent

    for outcome <- ~w(failed unknown) do
      report_c = %{
        c
        | event:
            Input.event(c, "result", %{
              "path" => [],
              "ref" => "journal:result",
              "stage" => "protocol_response",
              "outcome" => outcome,
              "report_contract" => nil
            })
      }

      r = Journal.receipt(report_c.event)

      stage =
        sent_receipts[[]]
        |> Map.put("protocol_response", r)
        |> Map.put("terminal", r)

      plan =
        %{
          sent_plan
          | status: if(outcome == "failed", do: "partial", else: "unknown"),
            rows: [{[], "effect", outcome, 20, 15_020, nil}],
            receipts: %{[] => stage}
        }
        |> Map.put(:reason, if(outcome == "failed", do: "effect_failed", else: "effect_unknown"))

      result = Input.point(report_c, own_sent["run"])
      assert result === Journal.point(report_c, Input.prior(own_sent["run"]), plan)
      assert :ok == verify(report_c, Input.prior(own_sent["run"]), result)
      assert result["run"]["spent"] === owner.charges
    end

    late_c = %{held_c | time: %{held_c.time | "elapsed_ms" => 15_020}}
    late = Input.point(late_c, first_reference["run"])

    late_plan =
      %{held_plan | status: "expired", rows: [{[], "effect", "cancelled", 20, 15_020, nil}]}
      |> Map.put(:reason, "deadline_elapsed")

    assert late === Journal.point(late_c, Input.prior(first_reference["run"]), late_plan)
    assert :ok == verify(late_c, Input.prior(first_reference["run"]), late)

    sequence = %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [Input.effect("sent"), Input.effect("dependent", true)]
    }

    seq = Input.compile(base, "journal:dependent", steps: sequence, run_ms: 20_000)

    rows = [
      {[], "sequence", "waiting", 20, 20_020, nil},
      {[0], "effect", "proposed", 20, 15_020, nil},
      {[1], "effect", "unsent", nil, nil, nil}
    ]

    first = Input.point(seq)

    initial_reference =
      Journal.point(seq, Input.prior(), %{status: "running", rows: rows, new: [{[0], false}]})

    assert first === initial_reference

    admit_c = %{
      seq
      | event:
          Input.event(seq, "admission", %{
            "path" => [0],
            "ref" => "journal:dependent:charge",
            "outcome" => "held"
          })
    }

    held_history = %{[0] => %{"admission" => Journal.receipt(admit_c.event)}}

    held_plan = %{
      status: "running",
      rows: List.replace_at(rows, 1, {[0], "effect", "reserved", 20, 15_020, nil}),
      receipts: held_history
    }

    held = Input.point(admit_c, first["run"])
    held_reference = Journal.point(admit_c, Input.prior(initial_reference["run"]), held_plan)
    assert held === held_reference

    send_c = %{
      seq
      | event: Input.event(seq, "handoff", %{"path" => [0], "ref" => "journal:dependent:send"})
    }

    sent_history = %{[0] => Map.put(held_history[[0]], "handoff", Journal.receipt(send_c.event))}

    sent_plan = %{
      held_plan
      | rows: List.replace_at(rows, 1, {[0], "effect", "handed_off", 20, 15_020, nil}),
        receipts: sent_history
    }

    sent = Input.point(send_c, held["run"])
    sent_reference = Journal.point(send_c, Input.prior(held_reference["run"]), sent_plan)
    assert sent === sent_reference

    evidence = %{
      seq
      | event:
          Input.event(seq, "result", %{
            "path" => [0],
            "ref" => "journal:dependent:report",
            "outcome" => "accepted",
            "stage" => "reported_match",
            "report_contract" => report_contract(seq)
          }),
        time: %{seq.time | "elapsed_ms" => 15_020}
    }

    history = %{
      [0] => Map.put(sent_history[[0]], "reported_match", Journal.receipt(evidence.event))
    }

    stopped_rows = [
      {[], "sequence", "cancelled", 20, 20_020, nil},
      {[0], "effect", "completed", 20, 15_020, nil},
      {[1], "effect", "cancelled", nil, nil, nil}
    ]

    stopped =
      Journal.point(evidence, Input.prior(sent_reference["run"]), %{
        status: "expired",
        reason: "deadline_elapsed",
        rows: stopped_rows,
        receipts: history
      })

    actual = Input.point(evidence, sent["run"])
    assert actual === stopped
    assert :ok == verify(evidence, Input.prior(sent["run"]), actual)
    assert actual["proposals"] == [] and actual["run"]["spent"] === held_reference["run"]["spent"]

    child =
      Input.compile(base, "journal:short-child", condition: Input.literal(false), run_ms: 9).source

    invoke = %{
      "id" => "invoke",
      "kind" => "invoke",
      "routine_id" => "journal:short-child",
      "revision" => "1",
      "arguments" => %{}
    }

    invoking =
      Input.compile(base, "journal:invoke", steps: invoke, definitions: [child], run_ms: 20_000)

    before_plan = %{
      status: "blocked",
      reason: "condition_blocked",
      rows: [{[], "invoke", "waiting", 20, 29, nil}, {[0], "effect", "unsent", nil, nil, nil}]
    }

    initial = Input.point(invoking)
    assert initial === Journal.point(invoking, Input.prior(), before_plan)

    later = %{
      invoking
      | event: Input.event(invoking, "resume"),
        time: %{invoking.time | "elapsed_ms" => 29}
    }

    result = Input.point(later, initial["run"])

    plan = %{
      before_plan
      | status: "expired",
        reason: "deadline_elapsed",
        rows: [
          {[], "invoke", "cancelled", 20, 29, nil},
          {[0], "effect", "cancelled", nil, nil, nil}
        ]
    }

    assert result === Journal.point(later, Input.prior(initial["run"]), plan)
    assert :ok == verify(later, Input.prior(initial["run"]), result)
  end

  test "journal sample custody rejects false first, replacement and unqualified edges", base do
    trigger = %{
      "kind" => "edge",
      "binding" => "measurement",
      "direction" => "rising",
      "debounce_ms" => 0,
      "cooldown_ms" => 30,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    for grammar <- [1, 2] do
      selected =
        if grammar == 1,
          do: %{base | time: Map.drop(base.time, ~w(format utc_generation))},
          else: base

      c = Input.compile(selected, "journal:edge:#{grammar}", sensor: true, trigger: trigger)
      report = Input.sample(c, 1, 1000, 20)
      fact = report.snapshot["facts"]["measurement"]

      memory = %{
        "last_receipt_ms" => 20,
        "last_sequence" => 1,
        "last_fact_id" => "sample:1",
        "last_fact_digest" => Journal.hash(fact),
        "baseline" => false
      }

      owned_edge = Journal.edge(report, memory)
      first = Input.point(report)
      assert first === no_edge(report, Input.prior(), owned_edge)
      assert :ok == verify(report, Input.prior(), first)
      wrong = put_in(first, ["edge", "baseline"], true)
      assert {:ok, _} = Edge.new(wrong["edge"], c.program, c.profile, c.limits)
      assert {:error, %Error{code: :invalid_transition}} = verify(report, Input.prior(), wrong)

      next = Input.sample(c, 2, 3000, 35)
      fact = next.snapshot["facts"]["measurement"]

      memory = %{
        "last_receipt_ms" => 35,
        "last_sequence" => 2,
        "last_fact_id" => "sample:2",
        "last_fact_digest" => Journal.hash(fact),
        "baseline" => true,
        "cooldown_until_ms" => 65,
        "last_original" => "edge:2"
      }

      edge = Journal.edge(next, memory)

      expected =
        Journal.point(
          next,
          Input.prior(nil, owned_edge),
          Map.put(effect_plan(35, "proposed", new: true), :edge, edge)
        )

      actual = Input.point(next, nil, owned_edge)
      assert actual === expected
      assert :ok == verify(next, Input.prior(nil, owned_edge), actual)

      replacement =
        next
        |> put_in([:snapshot, "binding_bases", "measurement", "source_epoch"], "connection:new")
        |> put_in([:snapshot, "facts", "measurement", "source_epoch"], "connection:new")

      fact = replacement.snapshot["facts"]["measurement"]

      memory = %{
        "last_receipt_ms" => 35,
        "last_sequence" => 2,
        "last_fact_id" => "sample:2",
        "last_fact_digest" => Journal.hash(fact),
        "baseline" => true
      }

      reset = Input.point(replacement, nil, owned_edge)

      assert reset ===
               no_edge(replacement, Input.prior(nil, owned_edge), Journal.edge(replacement, memory))

      assert :ok == verify(replacement, Input.prior(nil, owned_edge), reset)

      unqualified = put_in(report, [:snapshot, "facts", "measurement", "quality"], "stale")
      result = Input.point(unqualified)
      assert result === no_edge(unqualified, Input.prior(), Journal.edge(unqualified, %{}))
      assert :ok == verify(unqualified, Input.prior(), result)
    end
  end

  test "journal publishes authenticated inert starts then obtains a fresh complete cut", base do
    members = [
      Input.compile(base, "journal:pause", steps: Input.delay(7)),
      Input.compile(base, "journal:ready", steps: Input.effect("ready", true))
    ]

    input = Input.input(base, members)
    captures = Map.new(members, &{&1.program.data["ir_digest"], &1})

    first_points =
      Enum.map(input["entries"], fn entry ->
        c = %{captures[entry["program"]["ir_digest"]] | snapshot: entry["snapshot"]}

        plan =
          if c.source["id"] == "journal:pause",
            do: delayed_plan("waiting", nil, []),
            else: %{effect_plan(20, "proposed", new: true) | new: [{[], true}]}

        Journal.point(c, entry["prior"], plan)
      end)

    ready = List.last(members)

    expected =
      owned_collection(base, input, first_points, [{Journal.proposal(ready, [], true), "proposed"}])

    actual = Input.collection(base, input)
    assert actual.data === expected
    owner = Journal.open(input)
    {owner, capture} = Journal.capture(owner)
    certificate = Input.decision(base, actual)
    assert certificate.data["cell"]["elapsed"] == %{"min" => 20, "max" => 26}
    current = Input.current(base, actual)

    assert {:ok, _} =
             Decision.check(
               certificate,
               put_in(current, ["input", "time", "elapsed_ms"], 26),
               base.profile,
               base.limits
             )

    owner = Journal.tick(owner, %{base.time | "elapsed_ms" => 28})
    expired = %{current | "input" => owner.input}

    assert {:error, %Error{code: :stale_decision_time}} =
             Decision.check(certificate, expired, base.profile, base.limits)

    assert :ok == Decision.verify_point(capture.input, actual, base.profile, base.limits)
    assert {:ok, owner} = Journal.commit_inert(owner, capture, actual.data, expected)
    assert owner.charges == []
    owner = Journal.restore(Journal.dump(owner))
    next = Journal.retained(owner)
    fresh = Input.collection(base, next)

    points =
      Enum.map(next["entries"], fn entry ->
        c = %{
          captures[entry["program"]["ir_digest"]]
          | snapshot: entry["snapshot"],
            event: entry["event"],
            time: next["time"]
        }

        plan =
          if c.source["id"] == "journal:pause",
            do: delayed_plan("completed", 28, [{[1], false}]),
            else: effect_plan(20, "proposed")

        Journal.point(c, entry["prior"], plan)
      end)

    pause = hd(members)

    pending = [
      {Journal.proposal(pause, [1], false), "proposed"},
      {Journal.proposal(ready, [], true), "proposed"}
    ]

    expected_fresh = owned_collection(base, next, points, pending)
    assert fresh.data === expected_fresh
    assert Enum.all?(points, &(&1["run"]["start_ms"] == 20))
    fresh_certificate = Input.decision(base, fresh)
    fresh_current = Input.current(base, fresh)

    own_arbitration =
      Journal.arbitrate(
        expected_fresh["proposals"],
        fresh_current["dispositions"],
        1,
        expected_fresh["collection_digest"]
      )

    assert Enum.map(own_arbitration["decisions"], & &1["outcome"]) == ~w(conflict conflict)
    assert fresh_current["arbitration"] === own_arbitration

    assert {:ok, checked} =
             Decision.check(fresh_certificate, fresh_current, base.profile, base.limits)

    assert checked["transitions"] === expected_fresh["transitions"]

    for edge <- [25, 27] do
      forged =
        certificate.data
        |> put_in(["cell", "elapsed", "max"], edge)
        |> Input.rehash("decision_digest")

      assert {:error, %Error{code: :invalid_collection_decision}} =
               Decision.to_map(forged, base.profile, base.limits)
    end

    pause_id = pause.program.data["ir_digest"]

    missing =
      actual.data
      |> update_in(
        ["input", "entries"],
        &Enum.reject(&1, fn entry -> entry["program"]["ir_digest"] == pause_id end)
      )
      |> update_in(
        ["transitions"],
        &Enum.reject(&1, fn row -> row["program_digest"] == pause_id end)
      )
      |> Input.rehash("collection_digest")

    assert {:error, %Error{code: :invalid_collection_decision}} =
             Decision.verify_point(input, missing, base.profile, base.limits)

    wait =
      Input.compile(base, "journal:negative:wait",
        steps: %{
          "id" => "wait",
          "kind" => "wait",
          "condition" => Input.literal(false),
          "timeout_ms" => 4
        }
      )

    fact =
      Input.compile(base, "journal:negative:fact", sensor: true, condition: Input.literal(false))
      |> Input.sample(1, 3000, 20)

    fact = %{
      fact
      | event: Input.event(fact, "manual"),
        snapshot: put_in(fact.snapshot, ["facts", "measurement", "expires_ms"], 25)
    }

    for {negative, boundary} <- [{wait, 24}, {fact, 25}] do
      cut = Input.collection(base, Input.input(base, [negative, ready]))
      decision = Input.decision(base, cut)
      assert decision.data["cell"]["elapsed"] == %{"min" => 20, "max" => boundary - 1}
      context = Input.current(base, cut)

      assert {:ok, _} =
               Decision.check(
                 decision,
                 put_in(context, ["input", "time", "elapsed_ms"], boundary - 1),
                 base.profile,
                 base.limits
               )

      assert {:error, %Error{code: :stale_decision_time}} =
               Decision.check(
                 decision,
                 put_in(context, ["input", "time", "elapsed_ms"], boundary),
                 base.profile,
                 base.limits
               )
    end

    schedule = "sha256:" <> String.duplicate("3", 64)

    window =
      Input.compile(base, "journal:negative:window",
        condition: Input.literal(false),
        trigger: %{"kind" => "due", "schedule_id" => "journal:window", "schedule_basis" => schedule}
      )

    window = %{
      window
      | event:
          Input.event(window, "due", %{
            "schedule_id" => "journal:window",
            "schedule_basis" => schedule,
            "due_ms" => base.time["utc_low_ms"],
            "late_window_ms" => 6,
            "clock_generation" => base.time["utc_generation"],
            "time_zone_basis" => schedule
          })
    }

    cut = Input.collection(base, Input.input(base, [window, ready]))
    decision = Input.decision(base, cut)
    assert decision.data["cell"]["utc_high"]["max"] == base.time["utc_high_ms"] + 5
    context = Input.current(base, cut)

    assert {:ok, _} =
             Decision.check(
               decision,
               put_in(context, ["input", "time", "utc_high_ms"], base.time["utc_high_ms"] + 5),
               base.profile,
               base.limits
             )

    assert {:error, %Error{code: :stale_decision_time}} =
             Decision.check(
               decision,
               put_in(context, ["input", "time", "utc_high_ms"], base.time["utc_high_ms"] + 6),
               base.profile,
               base.limits
             )
  end

  test "journal member records include every reserved contributor and capacity conflict before cutoff",
       base do
    scripts = [
      {Input.compile(base, "journal:member:a"), false},
      {Input.compile(base, "journal:member:b"), false},
      {Input.compile(base, "journal:member:c", steps: Input.effect("contrary", true)), true},
      {Input.compile(base, "journal:member:d", target: "separate"), false}
    ]

    input = Input.input(base, Enum.map(scripts, &elem(&1, 0)))

    plans =
      Map.new(scripts, fn {c, value} ->
        {c.program.data["ir_digest"],
         {c, %{effect_plan(20, "proposed", new: true) | new: [{[], value}]},
          [{[], value, "proposed"}]}}
      end)

    reference = scripted_cut(base, input, plans)
    first = Input.collection(base, input)
    assert first.data === reference
    owner = Journal.open(input)
    {owner, token} = Journal.capture(owner)
    assert {:ok, owner} = Journal.commit_inert(owner, token, first.data, reference)
    next = Journal.retained(owner)
    first_entry = hd(next["entries"])

    admit =
      Map.merge(first_entry["event"], %{
        "kind" => "admission",
        "path" => [],
        "ref" => "journal:member:charge",
        "outcome" => "held"
      })

    next = put_in(next, ["entries", Access.at(0), "event"], admit)
    holder = first_entry["program"]["ir_digest"]

    plans =
      Map.new(scripts, fn {c, value} ->
        status = if c.program.data["ir_digest"] == holder, do: "reserved", else: "proposed"

        receipt =
          if status == "reserved", do: %{[] => %{"admission" => Journal.receipt(admit)}}, else: %{}

        plan = Map.put(effect_plan(20, status), :receipts, receipt)
        {c.program.data["ir_digest"], {c, plan, [{[], value, status}]}}
      end)

    expected = scripted_cut(base, next, plans)
    held = Input.collection(base, next)
    assert held.data === expected
    assert Enum.count(expected["proposal_states"], &(&1["status"] == "reserved")) == 1
    assert Enum.all?(expected["transitions"], &(&1["result"]["proposals"] == []))
    owner = Journal.replace(owner, next)
    {owner, token} = Journal.capture(owner)
    assert {:ok, owner} = Journal.commit_inert(owner, token, held.data, expected)

    assert owner.charges == [
             %{
               "original" => Journal.original(elem(hd(scripts), 0), []),
               "ref" => "journal:member:charge"
             }
           ]

    decision = Input.decision(base, held)

    ds =
      Map.new(
        expected["proposals"],
        &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      )

    same =
      Enum.find(
        expected["proposals"],
        &(&1["thing_id"] == "urn:archive:shared" and &1["input"] == false)
      )["step_original"]

    contrary = Enum.find(expected["proposals"], & &1["input"])["step_original"]

    selected_pair =
      ds
      |> put_in([same, "override"], "selected")
      |> put_in([contrary, "override"], "selected")

    policies = [
      ds,
      put_in(ds, [same, "override"], "selected"),
      selected_pair,
      put_in(ds, [contrary, "constraint"], "unknown"),
      put_in(ds, [same, "constraint"], "refused"),
      put_in(ds, [contrary, "override"], "suppressed")
    ]

    for dispositions <- policies, batch <- [1, 2] do
      context = Input.current(base, held, batch, dispositions)

      expected_arbitration =
        Journal.arbitrate(expected["proposals"], dispositions, batch, expected["collection_digest"])

      assert context["arbitration"] === expected_arbitration
      assert {:ok, checked} = Decision.check(decision, context, base.profile, base.limits)
      assert checked["arbitration"] === expected_arbitration
      assert checked["transitions"] === owner.references
    end

    missing =
      held.data
      |> update_in(["proposals"], &Enum.drop(&1, -1))
      |> update_in(["proposal_states"], &Enum.drop(&1, -1))
      |> Input.rehash("collection_digest")

    assert {:error, %Error{code: :invalid_collection_decision}} =
             Decision.new(missing, base.profile, base.limits)

    context = Input.current(base, held)
    wrong = put_in(context, ["arbitration", "decisions"], [])

    assert {:error, %Error{code: :stale_decision_arbitration}} =
             Decision.check(decision, wrong, base.profile, base.limits)

    {input, plans} = capacity_ledger(base)
    expected = scripted_cut(base, input, plans)
    actual = Input.collection(base, input)
    assert actual.data === expected
    assert length(expected["proposals"]) == 1024 and length(expected["proposal_states"]) == 1024
    context = Input.current(base, actual, 16)

    expected_arbitration =
      Journal.arbitrate(
        expected["proposals"],
        context["dispositions"],
        16,
        expected["collection_digest"]
      )

    assert context["arbitration"] === expected_arbitration
    assert length(expected_arbitration["selected"]) == 16
    assert Enum.count(expected_arbitration["decisions"], &(&1["outcome"] == "conflict")) == 32

    assert Enum.count(expected_arbitration["decisions"], &(&1["outcome"] == "batch-deferred")) ==
             736

    certificate = Input.decision(base, actual)
    assert {:ok, checked} = Decision.check(certificate, context, base.profile, base.limits)
    assert checked["arbitration"] === expected_arbitration
    {:ok, profile} = Profile.new(%{base.profile.data | "pending_work" => 1023})
    narrow = %{base | profile: profile}
    {input, _} = capacity_ledger(narrow)
    over = Input.claimed(narrow, input)
    assert {:error, %Error{code: :pending_work_bound}} = Decision.new(over, profile, base.limits)
  end

  test "journal clock records preserve the complete point across current confidence changes",
       base do
    c = Input.compile(base, "journal:qualified-clock", sensor: true, source_time: true)
    report = Input.sample(c, 1, 3000, 20)

    c = %{
      report
      | event: c.event,
        snapshot: put_in(report.snapshot, ["facts", "measurement", "expires_ms"], 57)
    }

    input = Input.input(base, [c])
    plan = effect_plan(20, "proposed", new: true)

    expected =
      scripted_cut(base, input, %{
        c.program.data["ir_digest"] => {c, plan, [{[], false, "proposed"}]}
      })

    actual = Input.collection(base, input)
    assert actual.data === expected
    owner = Journal.open(input)
    {owner, token} = Journal.capture(owner)
    assert {:ok, owner} = Journal.commit_inert(owner, token, actual.data, expected)
    certificate = Input.decision(base, actual)
    fact = c.snapshot["facts"]["measurement"]
    {:ok, source, _} = DateTime.from_iso8601(fact["source_time"])
    center = DateTime.to_unix(source, :millisecond)
    lower = center + fact["source_uncertainty_ms"]

    upper =
      center - fact["source_uncertainty_ms"] + hd(c.context["bases"])["evidence"]["freshness_ms"]

    assert certificate.data["cell"]["elapsed"] == %{"min" => 20, "max" => 56}
    assert certificate.data["cell"]["utc_low"]["min"] == lower
    assert certificate.data["cell"]["utc_high"]["max"] == upper
    context = Input.current(base, actual)

    intervals = [{lower, upper}, {center + 350, center + 450}, {center + 550, center + 650}]

    for {low, high} <- intervals do
      time = %{base.time | "utc_low_ms" => low, "utc_high_ms" => high}
      current = %{context | "input" => %{input | "time" => time}}
      assert {:ok, checked} = Decision.check(certificate, current, base.profile, base.limits)
      assert checked["point_time"] === base.time and checked["checked_time"] === time
      assert checked["transitions"] === owner.references
    end

    for time <- [
          %{base.time | "utc_low_ms" => lower - 1},
          %{base.time | "utc_high_ms" => upper + 1},
          %{base.time | "utc_generation" => "changed"},
          %{base.time | "utc_generation" => nil, "utc_low_ms" => nil, "utc_high_ms" => nil},
          %{base.time | "clock_generation" => "changed"},
          %{base.time | "epoch" => "changed"},
          %{base.time | "elapsed_ms" => 19},
          Map.drop(base.time, ~w(format utc_generation))
        ] do
      assert {:error, %Error{code: :stale_decision_time}} =
               Decision.check(
                 certificate,
                 put_in(context, ["input", "time"], time),
                 base.profile,
                 base.limits
               )
    end

    changed =
      context
      |> put_in(["input", "entries", Access.at(0), "snapshot", "id"], "changed")
      |> put_in(["input", "time", "elapsed_ms"], 0)

    assert {:error, %Error{code: :stale_decision_input}} =
             Decision.check(certificate, changed, base.profile, base.limits)

    withdrawn = Journal.tick(owner, %{base.time | "epoch" => "changed"})
    assert withdrawn.revision > owner.revision

    c = Input.compile(base, "journal:elapsed-only")
    actual = Input.collection(base, Input.input(base, [c]))
    certificate = Input.decision(base, actual)
    assert certificate.data["cell"]["utc_mode"] == "ignored"
    context = Input.current(base, actual)

    for time <- [
          %{base.time | "utc_generation" => "different", "utc_low_ms" => -1, "utc_high_ms" => 1},
          %{base.time | "utc_generation" => nil, "utc_low_ms" => nil, "utc_high_ms" => nil}
        ] do
      assert {:ok, checked} =
               Decision.check(
                 certificate,
                 put_in(context, ["input", "time"], time),
                 base.profile,
                 base.limits
               )

      assert checked["transitions"] === actual.data["transitions"]
    end
  end

  test "journal publication boundaries refuse authority extensions and count complete request bytes",
       base do
    c = Input.compile(base, "journal:closed")
    input = Input.input(base, [c])

    expected =
      scripted_cut(base, input, %{
        c.program.data["ir_digest"] =>
          {c, effect_plan(20, "proposed", new: true), [{[], false, "proposed"}]}
      })

    collection = Input.collection(base, input)
    assert collection.data === expected
    certificate = Input.decision(base, collection)

    malformed = [nil, self(), [true | false], %{"__struct__" => "Decision"}]

    for value <- [Map.put(certificate, :authority, :granted) | malformed] do
      assert {:error, %Error{}} = Decision.to_map(value, base.profile, base.limits)
    end

    for field <- Map.keys(certificate.data) do
      assert {:error, %Error{}} =
               Decision.to_map(Map.delete(certificate.data, field), base.profile, base.limits)
    end

    assert {:error, %Error{}} =
             Decision.new(Map.put(collection, :extra, true), base.profile, base.limits)

    assert {:error, %Error{}} =
             Decision.verify_point(
               input,
               Map.put(expected, "authorized", true),
               base.profile,
               base.limits
             )

    current = Input.current(base, collection)

    assert {:error, %Error{}} =
             Decision.check(
               certificate,
               Map.put(current, "authorized", true),
               base.profile,
               base.limits
             )

    assert :ok = Decision.verify_point(input, expected, base.profile, base.limits)
    {:ok, legacy} = Collection.evaluate(Map.delete(input, "format"), base.profile, base.limits)

    assert {:error, %Error{code: :unsupported_decision_scope}} =
             Decision.new(legacy, base.profile, base.limits)

    scope_path =
      Path.join(to_string(:code.priv_dir(:wotex_routines)), "vectors/wro-04-receipt-prefix.json")

    scope =
      scope_path
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("scope")

    scope = %{scope | "environment" => "manual_receipts_complete_pending_arbitration"}

    assert {:error, %Error{code: :unsupported_model_scope}} =
             Model.compile(c.program, scope, base.profile, base.limits)

    for operation <- [:point, :certificate, :projection, :current] do
      maximum = find_request_bound(base, operation, 1_000_000, 8)
      sample = bounded_sample(base, maximum, operation, true)
      result = bounded_call(sample, operation)
      assert result == :ok or match?({:ok, _}, result)

      assert {:error, %Error{code: :limit_or_json_error}} =
               base
               |> bounded_sample(maximum - 1, operation, false)
               |> bounded_call(operation)
    end
  end

  defp find_request_bound(_, _, _, 0),
    do: flunk("complete byte envelope did not reach a fixed bound")

  defp find_request_bound(base, operation, candidate, attempts) do
    sample = bounded_sample(base, candidate, operation, true)

    request =
      case operation do
        :point -> %{"input" => sample.input, "collection" => sample.collection.data}
        :certificate -> %{"collection" => sample.collection.data}
        :projection -> %{"decision" => sample.certificate.data}
        :current -> %{"decision" => sample.certificate.data, "context" => sample.current}
      end

    request =
      Map.merge(request, %{"profile" => base.profile.data, "json_limits" => sample.limits.data})

    output_size = if operation == :certificate, do: encoded_size(sample.certificate.data), else: 0
    required = max(encoded_size(request), output_size)

    if candidate == required,
      do: required,
      else: find_request_bound(base, operation, required, attempts - 1)
  end

  defp bounded_sample(base, maximum, operation, measuring) do
    {:ok, limits} = Limits.new(%{base.limits.data | "max_bytes" => maximum})
    base = %{base | limits: limits}
    c = Input.compile(base, "journal:bounded")
    input = Input.input(base, [c])
    point = Journal.point(c, Input.prior(), effect_plan(20, "proposed", new: true))

    expected =
      owned_collection(base, input, [point], [{Journal.proposal(c, [], false), "proposed"}])

    collection = Input.collection(base, input)
    assert collection.data === expected

    certificate =
      if operation in [:projection, :current] or (operation == :certificate and measuring),
        do: Input.decision(base, collection)

    %{
      input: input,
      collection: collection,
      certificate: certificate,
      current: if(operation == :current, do: Input.current(base, collection)),
      profile: base.profile,
      limits: limits
    }
  end

  defp bounded_call(sample, operation) do
    case operation do
      :point ->
        Decision.verify_point(sample.input, sample.collection, sample.profile, sample.limits)

      :certificate ->
        Decision.new(sample.collection, sample.profile, sample.limits)

      :projection ->
        Decision.to_map(sample.certificate, sample.profile, sample.limits)

      :current ->
        Decision.check(sample.certificate, sample.current, sample.profile, sample.limits)
    end
  end

  defp encoded_size(value) do
    {:ok, encoded} =
      Wotex.JSON.encode(value,
        max_bytes: 67_108_864,
        max_depth: 64,
        max_nodes: 2_000_000,
        max_collection_size: 8192,
        max_string_bytes: 65_536
      )

    byte_size(encoded)
  end

  defp scripted_cut(base, input, scripts) do
    {points, pending} =
      Enum.map(input["entries"], fn entry ->
        {member, plan, eligible} = scripts[entry["program"]["ir_digest"]]
        c = %{member | snapshot: entry["snapshot"], event: entry["event"], time: input["time"]}
        point = Journal.point(c, entry["prior"], plan)

        pending =
          Enum.map(eligible, fn {path, value, status} ->
            {Journal.proposal(c, path, value), status}
          end)

        {point, pending}
      end)
      |> Enum.unzip()

    owned_collection(base, input, points, List.flatten(pending))
  end

  defp capacity_ledger(base) do
    rows = [
      {[], "parallel", "waiting", 20, 1020, nil}
      | Enum.flat_map(0..3, fn group ->
          [
            {[group], "parallel", "waiting", 20, 1020, nil}
            | Enum.map(0..3, &{[group, &1], "effect", "proposed", 20, 1020, nil})
          ]
        end)
    ]

    paths = for group <- 0..3, leaf <- 0..3, do: [group, leaf]

    declarations =
      Enum.map(1..64, fn index ->
        value = index == 64
        target = if value, do: "journal:slot:1", else: "journal:slot:#{index}"

        steps = %{
          "id" => "matrix",
          "kind" => "parallel",
          "branches" =>
            Enum.map(0..3, fn group ->
              %{
                "id" => "part:#{group}",
                "kind" => "parallel",
                "branches" => Enum.map(0..3, &Input.effect("member:#{group}:#{&1}", value))
              }
            end)
        }

        c = Input.compile(base, "journal:capacity:#{index}", steps: steps, target: target)
        emitted = Enum.map(paths, &{&1, value})

        {c, %{status: "running", rows: rows, new: emitted},
         Enum.map(paths, &{&1, value, "proposed"})}
      end)

    input = Input.input(base, Enum.map(declarations, &elem(&1, 0)))

    scripts =
      Map.new(declarations, fn {c, plan, eligible} ->
        {c.program.data["ir_digest"], {c, plan, eligible}}
      end)

    {input, scripts}
  end

  defp no_edge(c, prior, edge),
    do: %{
      "run" => nil,
      "proposals" => [],
      "outcome" => "no-edge",
      "edge" => edge,
      "basis" => Journal.basis(c, prior)
    }

  defp effect_plan(start, status, opts \\ []),
    do: %{
      status: "running",
      rows: [{[], "effect", status, start, start + 1000, nil}],
      new: if(opts[:new], do: [{[], false}], else: [])
    }

  defp delayed_plan(delay_status, effect_start, emitted),
    do: %{
      status: "running",
      rows: [
        {[], "sequence", "waiting", 20, 1020, nil},
        {[0], "delay", delay_status, 20, 1020, nil},
        {[1], "effect", if(effect_start, do: "proposed", else: "unsent"), effect_start,
         if(effect_start, do: 1020, else: nil), nil}
      ],
      new: emitted
    }

  defp report_contract(c), do: Enum.at(c.context["bases"], 2)["evidence"]["report_contract"]

  defp verify(c, prior, result),
    do:
      Transition.verify(c.program, c.event, c.snapshot, c.time, prior, result, c.profile, c.limits)

  defp owned_collection(base, input, points, pending) do
    transitions =
      Enum.map(points, &%{"program_digest" => &1["basis"]["program_digest"], "result" => &1})
      |> Enum.sort_by(& &1["program_digest"])

    pending = Enum.sort_by(pending, fn {p, _} -> {p["program_digest"], p["path"]} end)
    proposals = Enum.map(pending, &elem(&1, 0))

    states =
      Enum.map(pending, fn {p, status} ->
        %{"step_original" => p["step_original"], "status" => status}
      end)

    Journal.collection(input, transitions, proposals, states, base.profile.data, base.limits.data)
  end
end
