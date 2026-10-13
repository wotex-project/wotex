defmodule Wotex.Routines.KernelTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Wotex.Routines.{Compiler, Error, Event, Kernel, Limits, Profile, Run}

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
    basis = Enum.at(corpus["bases"], 2)
    sensor = hd(corpus["bases"])
    fact = corpus["fact"]

    context = %{
      "registry" => corpus["registry"],
      "bases" => corpus["bases"],
      "bindings" => %{
        "actuator" => %{
          "basis" => Map.take(basis, ~w(id version semantic_digest)),
          "thing_id" => "urn:workcell:output",
          "resource_roles" => %{"target" => "resource:1"}
        },
        "sensor" => %{
          "basis" => Map.take(sensor, ~w(id version semantic_digest)),
          "thing_id" => fact["thing_id"],
          "resource_roles" => %{}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "procedure",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ["actuator", "sensor"],
      "trigger" => %{"kind" => "manual"},
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => effect("apply"),
      "overlap" => "reject",
      "run_ms" => 1000
    }

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => 20,
      "clock_generation" => "clock:1",
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    %{
      corpus: corpus,
      limits: limits,
      profile: profile,
      context: context,
      source: source,
      time: time
    }
  end

  test "one inert proposal retains complete basis and duplicate original never proposes twice", c do
    c = compile(c)
    assert {:ok, first} = advance(c)
    assert first["outcome"] == "running"
    assert [proposal] = first["proposals"]
    assert proposal["input"] == false
    assert proposal["resource_domains"] == ["resource:1"]
    assert first["basis"]["snapshot"] == c.snapshot
    assert first["basis"]["event"] == c.event
    assert step(first, []) == "proposed"
    assert {:ok, repeat} = advance(c, first["run"])
    assert repeat["proposals"] == []
    assert repeat["run"] == first["run"]
    assert Run.to_map(first["run"], c.program, c.profile, c.limits) == {:ok, first["run"]}

    schema =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("schemas/wro-02-execution.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, first["run"]) == :ok
    assert ExJsonSchema.Validator.validate(schema, c.event) == :ok
  end

  test "queue and ACK do not satisfy a reported-match sequence", c do
    c =
      compile(c, %{"id" => "ordered", "kind" => "sequence", "steps" => [effect("a"), effect("b")]})

    {:ok, first} = advance(c)
    assert Enum.map(first["proposals"], & &1["path"]) == [[0]]
    held = receive(c, first, "admission", [0], %{"outcome" => "held"})
    assert step(held, [0]) == "reserved"
    handed = receive(c, held, "handoff", [0])
    queued = result(c, handed, [0], "local_queue")
    ack = result(c, queued, [0], "protocol_response")
    assert step(ack, [0]) == "handed_off"
    assert ack["proposals"] == []
    matched = result(c, ack, [0], "reported_match")
    assert step(matched, [0]) == "completed"
    assert Enum.map(matched["proposals"], & &1["path"]) == [[1]]
    assert length(matched["run"]["spent"]) == 1

    second =
      matched
      |> then(&receive(c, &1, "admission", [1], %{"outcome" => "held"}))
      |> then(&receive(c, &1, "handoff", [1]))
      |> then(&result(c, &1, [1], "reported_match"))

    assert second["outcome"] == "completed"
    assert length(second["run"]["spent"]) == 2
  end

  test "exact receipt replay retains the first slot and conflicting/out-of-order input refuses",
       c do
    c = compile(c)
    {:ok, first} = advance(c)
    event = receipt(c, "admission", [], %{"outcome" => "held"})
    assert {:ok, held} = advance(%{c | event: event}, first["run"])
    assert {:ok, duplicate} = advance(%{c | event: event}, held["run"])
    assert held == duplicate

    assert {:error, %Error{code: :conflicting_receipt}} =
             advance(%{c | event: %{event | "ref" => "different"}}, held["run"])

    assert {:error, %Error{code: :out_of_order_receipt}} =
             advance(
               %{c | event: receipt(c, "result", [], report(c, "reported_match"))},
               held["run"]
             )

    handed = receive(c, held, "handoff", [])
    matched = result(c, handed, [], "reported_match")

    assert {:error, %Error{code: :out_of_order_receipt}} =
             advance(
               %{c | event: receipt(c, "result", [], report(c, "protocol_response"))},
               matched["run"]
             )

    bad =
      Map.put(report(c, "reported_match"), "report_contract", %{
        "id" => "other",
        "version" => "1",
        "semantic_digest" => "sha256:" <> String.duplicate("9", 64)
      })

    assert {:error, %Error{code: :stale_report_contract}} =
             advance(%{c | event: receipt(c, "result", [], bad)}, handed["run"])
  end

  test "parallel failure preserves handoffs and spends, cancels future work, and never resends",
       c do
    c =
      compile(c, %{"id" => "fork", "kind" => "parallel", "branches" => [effect("a"), effect("b")]})

    {:ok, first} = advance(c)

    both =
      first
      |> then(&receive(c, &1, "admission", [0], %{"outcome" => "held"}))
      |> then(&receive(c, &1, "handoff", [0]))
      |> then(&receive(c, &1, "admission", [1], %{"outcome" => "held"}))
      |> then(&receive(c, &1, "handoff", [1]))

    failed = result(c, both, [0], "protocol_response", "failed")
    assert failed["outcome"] == "partial"
    assert step(failed, [0]) == "failed"
    assert step(failed, [1]) == "unknown"
    assert length(failed["run"]["spent"]) == 2
    assert {:ok, replay} = advance(c, failed["run"])
    assert replay["proposals"] == []
    assert replay["run"]["spent"] == failed["run"]["spent"]
  end

  test "post-handoff cancellation retains later evidence without compensation or continuation", c do
    c =
      compile(c, %{"id" => "ordered", "kind" => "sequence", "steps" => [effect("a"), effect("b")]})

    {:ok, first} = advance(c)

    handed =
      first
      |> then(&receive(c, &1, "admission", [0], %{"outcome" => "held"}))
      |> then(&receive(c, &1, "handoff", [0]))

    assert {:ok, cancelled} = advance(%{c | event: %{c.event | "kind" => "cancel"}}, handed["run"])
    assert step(cancelled, [0]) == "unknown"
    assert step(cancelled, [1]) == "cancelled"
    assert cancelled["outcome"] == "cancelled"
    later = result(c, cancelled, [0], "reported_match")
    assert step(later, [0]) == "completed"
    assert later["outcome"] == "cancelled"
    assert later["proposals"] == []
    assert later["run"]["spent"] == handed["run"]["spent"]
  end

  test "delay uses elapsed boundaries; timeout, generation change and regression expire work", c do
    c =
      compile(c, %{
        "id" => "ordered",
        "kind" => "sequence",
        "steps" => [
          %{"id" => "pause", "kind" => "delay", "duration_ms" => 100},
          effect("after")
        ]
      })

    {:ok, first} = advance(c)
    assert first["proposals"] == []
    assert {:ok, before} = advance(%{c | time: %{c.time | "elapsed_ms" => 119}}, first["run"])
    assert before["proposals"] == []
    assert {:ok, ready} = advance(%{c | time: %{c.time | "elapsed_ms" => 120}}, before["run"])
    assert Enum.map(ready["proposals"], & &1["path"]) == [[1]]

    for time <- [
          %{c.time | "epoch" => "boot:2"},
          %{c.time | "clock_generation" => "clock:2"},
          %{c.time | "elapsed_ms" => 19},
          %{c.time | "elapsed_ms" => 1020}
        ] do
      assert {:ok, expired} = advance(%{c | time: time}, first["run"])
      assert expired["outcome"] == "expired"
      assert expired["proposals"] == []
    end

    c =
      compile(c, %{
        "id" => "await",
        "kind" => "wait",
        "condition" => %{"op" => "literal", "value" => "unknown"},
        "timeout_ms" => 100
      })

    {:ok, waiting} = advance(c)
    assert {:ok, timed_out} = advance(%{c | time: %{c.time | "elapsed_ms" => 120}}, waiting["run"])
    assert timed_out["run"]["reason"] == "wait_timeout"
  end

  test "full due confidence must fit the original half-open window and cannot drift", c do
    source = %{c.source | "trigger" => %{"kind" => "due", "schedule_id" => "calendar:1"}}
    c = compile(%{c | source: source})

    due =
      Map.merge(c.event, %{
        "kind" => "due",
        "schedule_id" => "calendar:1",
        "due_ms" => 1000,
        "late_window_ms" => 100,
        "clock_generation" => "clock:1",
        "time_zone_basis" => "sha256:" <> String.duplicate("6", 64)
      })

    c = %{c | event: due, time: %{c.time | "utc_low_ms" => 1000, "utc_high_ms" => 1099}}
    assert {:ok, first} = advance(c)
    assert length(first["proposals"]) == 1

    for time <- [
          %{c.time | "utc_low_ms" => 999},
          %{c.time | "utc_high_ms" => 1100},
          %{c.time | "utc_low_ms" => nil, "utc_high_ms" => nil}
        ] do
      assert {:ok, expired} = advance(%{c | time: time})
      assert expired["outcome"] == "expired"
      assert expired["proposals"] == []
    end

    assert {:error, %Error{code: :stale_due_window}} =
             advance(%{c | event: %{due | "due_ms" => 1001}}, first["run"])
  end

  test "busy overlap and missing, foreign, malformed and altered retained values refuse", c do
    c = compile(c)
    {:ok, first} = advance(c)
    other = %{c | event: %{c.event | "original" => "original:2"}}

    assert {:ok, skipped} =
             Kernel.advance(
               other.program,
               other.event,
               other.snapshot,
               other.time,
               %{"original" => nil, "busy" => first["run"], "edge" => nil},
               c.profile,
               c.limits
             )

    assert skipped["outcome"] == "skipped-busy"
    assert skipped["run"] == nil
    assert {:error, %Error{code: :foreign_original}} = advance(other, first["run"])

    assert {:error, %Error{code: :missing_original}} =
             advance(%{c | event: receipt(c, "handoff", [])})

    for changed <- [
          put_in(first["run"], ["steps", Access.at(0), "path"], [1]),
          %{first["run"] | "spent" => [%{"original" => "forged", "ref" => "ref"}]},
          %{first["run"] | "source_digest" => "altered"}
        ] do
      assert {:error, %Error{}} = Run.new(changed, c.program, c.profile, c.limits)
    end

    assert {:error, %Error{}} = Event.new(%{c.event | "kind" => "unknown"}, c.limits)
    assert {:error, %Error{}} = Event.new(struct!(Event, data: nil), c.limits)
  end

  test "conditional selection stays fixed while root conditions gate each new effect", c do
    predicate = %{"op" => "gt", "binding" => "sensor", "value" => 2000}

    branches = %{
      "id" => "choose",
      "kind" => "if",
      "condition" => predicate,
      "then" => %{
        "id" => "yes",
        "kind" => "sequence",
        "steps" => [
          %{"id" => "pause", "kind" => "delay", "duration_ms" => 100},
          effect("a")
        ]
      },
      "else" => effect("b")
    }

    c = compile(c, branches)
    fact = %{c.corpus["fact"] | "source_time_trust" => "untrusted"}
    # Missing required clock qualification is unknown, never an else selection.
    assert {:ok, blocked} = advance(%{c | snapshot: put_in(c.snapshot, ["facts", "sensor"], fact)})
    assert blocked["outcome"] == "blocked"
    {:ok, date, _} = DateTime.from_iso8601(c.corpus["fact"]["source_time"])
    utc = DateTime.to_unix(date, :millisecond) + 500

    c = %{
      c
      | time: %{c.time | "utc_low_ms" => utc, "utc_high_ms" => utc},
        snapshot: put_in(c.snapshot, ["facts", "sensor"], c.corpus["fact"])
    }

    assert {:ok, selected} = advance(c)
    assert hd(selected["run"]["steps"])["branch"] == "then"

    later = %{
      c
      | time: %{c.time | "elapsed_ms" => 120},
        snapshot: put_in(c.snapshot, ["facts", "sensor", "value"], 1000)
    }

    assert {:ok, ready} = advance(later, selected["run"])
    assert Enum.map(ready["proposals"], & &1["path"]) == [[0, 1]]
    assert hd(ready["run"]["steps"])["branch"] == "then"

    assert Enum.find(c.program.data["ir"]["steps"]["then"]["steps"], &(&1["kind"] == "delay"))[
             "path"
           ] == [0, 0]

    source = %{c.source | "condition" => predicate}
    c = compile(%{c | source: source}, branches)
    assert {:ok, selected} = advance(c)

    assert {:ok, blocked} =
             advance(
               %{
                 later
                 | program: c.program,
                   snapshot: %{later.snapshot | "active_programs" => [c.program.data["ir_digest"]]},
                   event: c.event
               },
               selected["run"]
             )

    assert blocked["outcome"] == "blocked"
    assert blocked["proposals"] == []
  end

  test "retained completion, elapsed and join claims cannot widen installed semantics", c do
    c = compile(c)
    {:ok, first} = advance(c)

    handed =
      first
      |> then(&receive(c, &1, "admission", [], %{"outcome" => "held"}))
      |> then(&receive(c, &1, "handoff", []))

    ack = result(c, handed, [], "protocol_response")
    forged = put_in(ack["run"], ["steps", Access.at(0), "status"], "completed")

    assert {:error, %Error{code: :incoherent_receipts}} =
             Run.new(forged, c.program, c.profile, c.limits)

    forged = %{first["run"] | "deadline_ms" => first["run"]["deadline_ms"] + 1}

    assert {:error, %Error{code: :incoherent_run_time}} =
             Run.new(forged, c.program, c.profile, c.limits)

    forged = %{first["run"] | "status" => "completed"}

    assert {:error, %Error{code: :incoherent_run_status}} =
             Run.new(forged, c.program, c.profile, c.limits)

    assert {:error, %Error{code: :missing_original}} =
             Kernel.advance(
               c.program,
               c.event,
               c.snapshot,
               c.time,
               %{"original" => nil, "busy" => first["run"], "edge" => nil},
               c.profile,
               c.limits
             )

    c = compile(c, %{"id" => "delay", "kind" => "delay", "duration_ms" => 100})
    {:ok, waiting} = advance(c)
    forged = put_in(waiting["run"], ["steps", Access.at(0), "status"], "completed")

    assert {:error, %Error{code: :premature_delay}} =
             Run.new(forged, c.program, c.profile, c.limits)
  end

  test "child condition and duration stay bound to the expanded invocation", c do
    child = %{
      c.source
      | "id" => "child",
        "condition" => %{"op" => "literal", "value" => false},
        "run_ms" => 100
    }

    source = %{
      c.source
      | "steps" => %{
          "id" => "call",
          "kind" => "invoke",
          "routine_id" => "child",
          "revision" => "1",
          "arguments" => %{}
        }
    }

    c = compile(%{c | source: source, context: %{c.context | "definitions" => [child]}})
    assert {:ok, blocked} = advance(c)
    assert blocked["outcome"] == "blocked"
    assert blocked["proposals"] == []
    assert {:ok, expired} = advance(%{c | time: %{c.time | "elapsed_ms" => 120}}, blocked["run"])
    assert expired["outcome"] == "expired"
    assert expired["proposals"] == []
  end

  test "receipt refusal and unknown stop sequence continuation and preserve original accounting",
       c do
    c =
      compile(c, %{"id" => "ordered", "kind" => "sequence", "steps" => [effect("a"), effect("b")]})

    {:ok, first} = advance(c)
    refused = receive(c, first, "admission", [0], %{"outcome" => "refused"})
    assert refused["proposals"] == []
    assert step(refused, [1]) == "cancelled"
    assert refused["run"]["spent"] == []

    handed =
      first
      |> then(&receive(c, &1, "admission", [0], %{"outcome" => "held"}))
      |> then(&receive(c, &1, "handoff", [0]))

    unknown = result(c, handed, [0], "protocol_response", "unknown")
    assert unknown["outcome"] == "unknown"
    assert step(unknown, [1]) == "cancelled"
    assert length(unknown["run"]["spent"]) == 1
    assert {:ok, repeat} = advance(c, unknown["run"])
    assert repeat["proposals"] == []
  end

  defp compile(c, steps \\ nil) do
    source = if steps, do: %{c.source | "steps" => steps}, else: c.source
    {:ok, program} = Compiler.compile(source, c.context, c.profile, c.limits)

    snapshot = %{
      "id" => "snapshot:1",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{
        "urn:workcell:output" => 1,
        "resource:1" => 1,
        c.corpus["fact"]["thing_id"] => 1
      },
      "binding_bases" => %{
        "actuator" => %{
          "profile_digest" => c.context["bindings"]["actuator"]["basis"]["semantic_digest"],
          "source_id" => "device:1",
          "source_epoch" => "connection:1",
          "source_time_basis" => nil
        },
        "sensor" =>
          Map.take(c.corpus["fact"], ~w(profile_digest source_id source_epoch source_time_basis))
      },
      "facts" => %{"actuator" => nil, "sensor" => nil}
    }

    Map.merge(c, %{
      program: program,
      snapshot: snapshot,
      event: %{
        "kind" => "manual",
        "original" => "original:1",
        "program_digest" => program.data["ir_digest"]
      }
    })
  end

  defp effect(id),
    do: %{
      "id" => id,
      "kind" => "effect",
      "binding" => "actuator",
      "input" => false,
      "completion" => "reported_match"
    }

  defp advance(c, run \\ nil),
    do:
      Kernel.advance(
        c.program,
        c.event,
        c.snapshot,
        c.time,
        %{"original" => run, "busy" => nil, "edge" => nil},
        c.profile,
        c.limits
      )

  defp step(result, path), do: Enum.find(result["run"]["steps"], &(&1["path"] == path))["status"]

  defp receipt(c, kind, path, fields \\ %{}),
    do:
      Map.merge(
        %{
          "kind" => kind,
          "original" => c.event["original"],
          "program_digest" => c.event["program_digest"],
          "path" => path,
          "ref" => "receipt:" <> kind <> inspect(path) <> Map.get(fields, "stage", "")
        },
        fields
      )

  defp receive(c, result, kind, path, fields \\ %{}) do
    assert {:ok, next} = advance(%{c | event: receipt(c, kind, path, fields)}, result["run"])
    next
  end

  defp report(c, stage, outcome \\ "accepted"),
    do: %{
      "stage" => stage,
      "outcome" => outcome,
      "report_contract" =>
        if(stage in ~w(correlated_report reported_match),
          do: Enum.at(c.corpus["bases"], 2)["evidence"]["report_contract"],
          else: nil
        )
    }

  defp result(c, previous, path, stage, outcome \\ "accepted"),
    do: receive(c, previous, "result", path, report(c, stage, outcome))
end
