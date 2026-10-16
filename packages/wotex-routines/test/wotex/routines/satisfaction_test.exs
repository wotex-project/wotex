Code.require_file("../../support/continuation_fixtures.exs", __DIR__)

defmodule Wotex.Routines.SatisfactionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Basis, Error, Event, Model, Run, Witness}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F

  test "matching Boolean, integer and enum facts complete an unsent property without stage receipts" do
    for {type, input} <- [{"boolean", false}, {"integer", 2500}, {"enum", "off"}] do
      c = fixture(type: type, input: input)
      {:ok, first} = F.advance(c)
      matched = satisfaction(c)
      assert {:ok, result} = F.advance(matched, first["run"])
      assert result["outcome"] == "completed"
      assert result["proposals"] == []
      assert result["run"]["format"] == "wotex.routines.run@2"
      assert result["run"]["time_format"] == "wotex.routines.time@1"
      assert result["run"]["spent"] == []
      [record] = result["run"]["steps"]
      assert record["status"] == "completed"
      assert %{"ref" => "satisfied:1", "outcome" => "matched"} = record["receipts"]["satisfied"]

      assert Enum.all?(Map.drop(record["receipts"], ["satisfied"]), fn {_, receipt} ->
               is_nil(receipt)
             end)

      assert {:ok, _} = Run.new(result["run"], c.program, c.profile, c.limits)
      assert :ok = ExJsonSchema.Validator.validate(schema("wro-02-continuation"), result["run"])

      assert Map.drop(result["run"], ~w(format time_format status steps)) ==
               Map.drop(first["run"], ~w(format status steps))
    end
  end

  test "a held reservation stays charged while sequence progress emits only its next step" do
    steps = %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [F.effect("first"), F.effect("second")]
    }

    c = fixture(source: %{"steps" => steps})
    {:ok, first} = F.advance(c)
    {:ok, held} = F.advance(receipt(c, "admission", [0]), first["run"])
    matched = satisfaction(c, [0])
    assert {:ok, result} = F.advance(matched, held["run"])
    assert result["run"]["spent"] == held["run"]["spent"]
    assert [%{"path" => [1]}] = result["proposals"]
    old = record(held["run"], [0])
    new = record(result["run"], [0])
    assert new["receipts"]["admission"] == old["receipts"]["admission"]
    assert Map.drop(new, ~w(status receipts)) == Map.drop(old, ~w(status receipts))
    assert record(result["run"], [1])["receipts"]["satisfied"] == nil
  end

  test "satisfaction events are closed, bounded and revalidated when native" do
    c = fixture() |> satisfaction()
    assert {:ok, event} = Event.new(c.event, c.limits)
    assert {:ok, data} = Event.to_map(event, c.limits)
    assert data == c.event

    for bad <- [
          Map.put(c.event, "stage", "reported_match"),
          Map.delete(c.event, "fact_id"),
          %{c.event | "fact_id" => ""},
          %{c.event | "path" => [-1]},
          %{c.event | "path" => List.duplicate(0, 33)},
          %{c.event | "report_contract" => nil},
          put_in(c.event, ["report_contract", "extra"], true)
        ] do
      assert {:error, %Error{}} = Event.new(bad, c.limits)
      assert {:error, %Error{}} = Event.to_map(%Event{data: bad}, c.limits)
    end
  end

  test "exact terminal duplicates retain history after facts disappear but conflicts refuse" do
    c = fixture()
    {:ok, first} = F.advance(c)
    matched = satisfaction(c)
    {:ok, completed} = F.advance(matched, first["run"])

    missing = %{
      matched
      | snapshot: put_in(matched.snapshot, ["facts", "actuator"], nil),
        time: %{c.time | "elapsed_ms" => 50_000}
    }

    assert {:ok, duplicate} = F.advance(missing, completed["run"])
    assert duplicate["run"] == completed["run"]
    assert duplicate["proposals"] == []

    assert {:error, %Error{code: :conflicting_receipt}} =
             F.advance(
               %{missing | event: %{missing.event | "ref" => "satisfied:2"}},
               completed["run"]
             )

    assert {:error, %Error{code: :out_of_order_receipt}} =
             F.advance(%{matched | event: Map.put(matched.event, "fact_id", "other")}, %{
               first["run"]
               | "status" => "cancelled",
                 "reason" => "cancelled",
                 "steps" => Enum.map(first["run"]["steps"], &Map.put(&1, "status", "cancelled"))
             })
  end

  test "current qualification refuses stale or foreign facts and source-age uncertainty" do
    c = fixture()
    {:ok, first} = F.advance(c)
    matched = satisfaction(c)

    changes = [
      %{"id" => "different"},
      %{"value" => true},
      %{"quality" => "stale"},
      %{"replay" => "retained"},
      %{"continuity" => "lost"},
      %{"source_id" => "other"},
      %{"source_epoch" => "other"},
      %{"receipt_epoch" => "other"},
      %{"expires_ms" => 20},
      %{"source_class" => "protocol_response"},
      %{"thing_id" => "urn:other"},
      %{"affordance_name" => "other"},
      %{"profile_digest" => "sha256:" <> String.duplicate("0", 64)}
    ]

    for change <- changes do
      changed = update_in(matched.snapshot, ["facts", "actuator"], &Map.merge(&1, change))

      assert {:error, %Error{code: :invalid_satisfaction}} =
               F.advance(%{matched | snapshot: changed}, first["run"])
    end

    assert {:error, %Error{code: :invalid_satisfaction}} =
             F.advance(
               %{matched | time: %{c.time | "utc_low_ms" => nil, "utc_high_ms" => nil}},
               first["run"]
             )

    assert {:error, %Error{code: :invalid_satisfaction}} =
             F.advance(
               %{matched | snapshot: put_in(matched.snapshot, ["facts", "actuator"], nil)},
               first["run"]
             )

    assert {:error, %Error{code: :stale_report_contract}} =
             F.advance(
               %{matched | event: put_in(matched.event, ["report_contract", "version"], "2")},
               first["run"]
             )
  end

  test "missing original and satisfaction after handoff refuse" do
    c = fixture()
    matched = satisfaction(c)
    assert {:error, %Error{code: :missing_original}} = F.advance(matched)
    {:ok, first} = F.advance(c)
    assert {:error, %Error{code: :missing_original}} = F.advance(matched, nil, nil, first["run"])
    {:ok, held} = F.advance(receipt(c, "admission"), first["run"])
    {:ok, sent} = F.advance(receipt(c, "handoff"), held["run"])
    assert {:error, %Error{code: :out_of_order_receipt}} = F.advance(matched, sent["run"])
  end

  test "expiry and deactivation precede fresh satisfaction and never promote the old run" do
    c = fixture(source: %{"run_ms" => 20_000})
    {:ok, first} = F.advance(c)
    matched = satisfaction(c)

    for time <- [
          %{c.time | "elapsed_ms" => 15_020},
          %{c.time | "epoch" => "boot:2"},
          %{c.time | "clock_generation" => "other"},
          %{c.time | "elapsed_ms" => 19}
        ] do
      assert {:ok, result} = F.advance(%{matched | time: time}, first["run"])
      assert result["outcome"] == "expired"
      assert result["run"]["format"] == "wotex.routines.run@1"
      assert result["proposals"] == []
    end

    inactive = %{matched | snapshot: %{matched.snapshot | "active_programs" => []}}
    assert {:ok, result} = F.advance(inactive, first["run"])
    assert result["outcome"] == "cancelled"
    assert result["run"]["reason"] == "inactive_program"
    assert result["run"]["format"] == "wotex.routines.run@1"
  end

  test "concrete replay recognizes current-state evidence without pretending to hand off" do
    c = fixture()
    matched = satisfaction(c)

    frames =
      Enum.map([c, matched], &%{"event" => &1.event, "snapshot" => &1.snapshot, "time" => &1.time})

    witness = %{
      "format" => "wotex.routines.witness@1",
      "property" => "completion_evidence",
      "program_digest" => c.program.data["ir_digest"],
      "source_digest" => c.program.data["source_digest"],
      "compiler_basis" => c.context["compiler_basis"],
      "max_steps" => 2,
      "max_originals" => 1,
      "initial" => %{"runs" => [], "edge" => nil},
      "frames" => frames
    }

    for property <- ~w(completion_evidence proposal_once held_spend_retained stopped_continuation) do
      witness = %{witness | "property" => property}
      assert {:ok, result} = Witness.replay(c.program, witness, c.profile, c.limits)
      assert result["reproduced"] == false
      assert List.last(result["transitions"])["outcome"] == "completed"
      assert :ok = ExJsonSchema.Validator.validate(schema("wro-04-witness"), witness)
      assert :ok = ExJsonSchema.Validator.validate(schema("wro-04-witness"), result)
    end
  end

  test "parallel joins require every branch and preserve independent originals" do
    steps = %{
      "id" => "parallel",
      "kind" => "parallel",
      "branches" => [F.effect("left"), F.effect("right")]
    }

    c = fixture(source: %{"steps" => steps})
    {:ok, first} = F.advance(c)
    assert {:ok, left} = F.advance(satisfaction(c, [0]), first["run"])
    assert left["outcome"] == "running"
    assert left["proposals"] == []
    assert record(left["run"], [1])["status"] == "proposed"
    assert {:ok, both} = F.advance(satisfaction(c, [1]), left["run"])
    assert both["outcome"] == "completed"
    assert both["proposals"] == []

    assert Enum.map(both["run"]["steps"], & &1["original"]) ==
             Enum.map(first["run"]["steps"], & &1["original"])

    receipt = record(both["run"], [0])["receipts"]["satisfied"]
    forged = put_in(both["run"], ["steps", Access.at(0), "receipts", "satisfied"], receipt)

    assert {:error, %Error{code: :incoherent_receipts}} =
             Run.new(forged, c.program, c.profile, c.limits)
  end

  test "current root and invoked conditions gate fresh satisfaction" do
    for invoked <- [false, true] do
      c = fixture(sensor: true)
      condition = %{"op" => "gt", "binding" => "sensor", "value" => 2000}

      c =
        if invoked do
          child = %{c.source | "id" => "child", "condition" => condition, "run_ms" => 100}
          context = %{c.context | "definitions" => [child]}

          steps = %{
            "id" => "call",
            "kind" => "invoke",
            "routine_id" => "child",
            "revision" => "1",
            "arguments" => %{}
          }

          F.compile(%{c | context: context}, %{"steps" => steps})
        else
          F.compile(c, %{"condition" => condition})
        end

      sample = F.sample(c, 1, 20, 3000)
      c = %{c | snapshot: sample.snapshot}
      {:ok, first} = F.advance(c)
      path = if invoked, do: [0], else: []
      matched = satisfaction(c, path)

      for fact <- [nil, %{sample.snapshot["facts"]["sensor"] | "value" => 1000}] do
        blocked = %{matched | snapshot: put_in(matched.snapshot, ["facts", "sensor"], fact)}
        assert {:error, %Error{code: :invalid_satisfaction}} = F.advance(blocked, first["run"])
      end

      assert {:ok, completed} = F.advance(matched, first["run"])
      assert completed["outcome"] == "completed"

      if invoked do
        assert {:ok, expired} =
                 F.advance(%{matched | time: %{c.time | "elapsed_ms" => 120}}, first["run"])

        assert expired["outcome"] == "expired"
        assert expired["run"]["format"] == "wotex.routines.run@1"
      end
    end
  end

  test "selected conditional paths remain fixed and unsent excluded paths refuse" do
    condition = %{"op" => "gt", "binding" => "sensor", "value" => 2000}

    steps = %{
      "id" => "choice",
      "kind" => "if",
      "condition" => condition,
      "then" => F.effect("yes"),
      "else" => F.effect("no")
    }

    c = fixture(sensor: true, source: %{"steps" => steps})
    sample = F.sample(c, 1, 20, 3000)
    c = %{c | snapshot: sample.snapshot}
    {:ok, first} = F.advance(c)
    c = %{c | snapshot: put_in(c.snapshot, ["facts", "sensor", "value"], 1000)}

    assert {:error, %Error{code: :out_of_order_receipt}} =
             F.advance(satisfaction(c, [1]), first["run"])

    assert {:ok, result} = F.advance(satisfaction(c, [0]), first["run"])
    assert result["outcome"] == "completed"
    assert record(result["run"], [])["branch"] == "then"
    assert record(result["run"], [1])["status"] == "unsent"
  end

  test "live duplicates retain receipts without facts while later deadlines still stop work" do
    steps = %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [F.effect("first"), F.effect("second")]
    }

    c = fixture(source: %{"steps" => steps, "run_ms" => 20_000})
    {:ok, first} = F.advance(c)
    matched = satisfaction(c, [0])
    {:ok, next} = F.advance(matched, first["run"])
    missing = %{matched | snapshot: put_in(matched.snapshot, ["facts", "actuator"], nil)}
    assert {:ok, duplicate} = F.advance(missing, next["run"])
    assert duplicate["run"] == next["run"]
    assert duplicate["proposals"] == []
    late = %{missing | time: %{c.time | "elapsed_ms" => 15_020}}
    assert {:ok, expired} = F.advance(late, next["run"])
    assert expired["outcome"] == "expired"
    assert expired["proposals"] == []
    assert record(expired["run"], [0])["receipts"] == record(next["run"], [0])["receipts"]
    assert record(expired["run"], [1])["status"] == "cancelled"
  end

  test "integer matches convert exactly and refuse inexact, missing or incompatible units" do
    c = fixture(type: "integer", input: 2500)
    {:ok, first} = F.advance(c)
    matched = satisfaction(c)

    unit = %{
      hd(c.context["bases"])["value"]["unit"]
      | "scale_d" => 1000,
        "offset_n" => 273_150,
        "offset_d" => 1000
    }

    exact =
      update_in(
        matched.snapshot,
        ["facts", "actuator"],
        &Map.merge(&1, %{"unit" => unit, "value" => 25_000})
      )

    assert {:ok, result} = F.advance(%{matched | snapshot: exact}, first["run"])
    assert result["outcome"] == "completed"

    for fact <- [
          %{exact["facts"]["actuator"] | "value" => 25_001},
          put_in(exact["facts"]["actuator"], ["unit", "dimension"], "power"),
          %{exact["facts"]["actuator"] | "unit" => nil},
          %{exact["facts"]["actuator"] | "value" => true, "unit" => nil}
        ] do
      assert {:error, %Error{code: :invalid_satisfaction}} =
               F.advance(
                 %{matched | snapshot: put_in(matched.snapshot, ["facts", "actuator"], fact)},
                 first["run"]
               )
    end
  end

  test "actions and protocol-only completion cannot use current-state satisfaction" do
    for {change, completion} <- [
          {&put_in(&1, ["affordance"], %{
             "type" => "action",
             "name" => "apply",
             "operation" => "invokeaction"
           }), "reported_match"},
          {&put_in(&1, ["evidence", "completion"], "protocol_response"), "protocol_response"}
        ] do
      c =
        fixture(
          basis: change,
          source: %{"steps" => %{F.effect("apply") | "completion" => completion}}
        )

      {:ok, first} = F.advance(c)

      assert {:error, %Error{code: :invalid_satisfaction}} =
               F.advance(satisfaction(c), first["run"])
    end
  end

  test "retained validation refuses mixed stages, forged status, removed spend and changed paths" do
    c = fixture()
    {:ok, first} = F.advance(c)
    {:ok, held} = F.advance(receipt(c, "admission"), first["run"])
    {:ok, matched} = F.advance(satisfaction(c), held["run"])
    run = matched["run"]
    receipt = hd(run["steps"])["receipts"]["satisfied"]

    for bad <- [
          put_in(run, ["steps", Access.at(0), "receipts", "handoff"], %{
            receipt
            | "outcome" => "marked"
          }),
          put_in(run, ["steps", Access.at(0), "receipts", "protocol_response"], %{
            receipt
            | "outcome" => "accepted"
          }),
          put_in(run, ["steps", Access.at(0), "receipts", "satisfied", "outcome"], "accepted"),
          put_in(run, ["steps", Access.at(0), "status"], "proposed"),
          put_in(run, ["steps", Access.at(0), "path"], [0]),
          %{run | "spent" => []},
          Map.delete(run, "time_format")
        ] do
      assert {:error, %Error{}} = Run.new(bad, c.program, c.profile, c.limits)
      assert {:error, %Error{}} = Run.to_map(%Run{data: bad}, c.program, c.profile, c.limits)
    end

    assert {:error, %Error{code: :out_of_order_receipt}} = F.advance(receipt(c, "handoff"), run)
  end

  test "Time@2 satisfaction retains its selected grammar through UTC correction and restart" do
    c = fixture()
    time = Map.merge(c.time, %{"format" => "wotex.routines.time@2", "utc_generation" => "utc:1"})
    c = %{c | time: time}
    {:ok, first} = F.advance(c)
    matched = satisfaction(%{c | time: %{time | "utc_generation" => "utc:2"}})
    assert {:ok, result} = F.advance(matched, first["run"])
    assert result["run"]["time_format"] == "wotex.routines.time@2"

    assert {:error, %Error{code: :clock_format_mismatch}} =
             F.advance(%{matched | time: Map.drop(time, ~w(format utc_generation))}, result["run"])

    restarted = %{F.resume(c) | time: %{time | "epoch" => "boot:2"}}
    assert {:ok, retained} = F.advance(restarted, result["run"])
    assert retained["run"] == result["run"]
    assert retained["proposals"] == []
  end

  test "scope requests for satisfaction refuse in frozen staged models" do
    c = fixture()

    scope = %{
      "profile" => "receipt-prefix@1",
      "purpose" => "software_receipt_transitions_only",
      "initial_history" => "no_existing_run",
      "time_policy" => "frozen_before_deadline",
      "environment" => "manual_staged_receipts_and_satisfaction_one_original",
      "claims" => ~w(proposal_once held_spend_retained completion_evidence stopped_continuation),
      "omissions" =>
        ~w(authority time_progress fact_changes multi_original_overlap complete_set_arbitration historical_receipts physical_effects),
      "policy_digest" => c.context["compiler_basis"]
    }

    assert {:error, %Error{code: :unsupported_model_scope}} =
             Model.compile(c.program, scope, c.profile, c.limits)
  end

  test "the immutable UTC due window expires before a fresh satisfaction" do
    trigger = %{
      "kind" => "due",
      "schedule_id" => "schedule:1",
      "schedule_basis" => "sha256:" <> String.duplicate("6", 64)
    }

    c = fixture(source: %{"trigger" => trigger})

    due =
      Map.merge(c.event, %{
        "kind" => "due",
        "schedule_id" => trigger["schedule_id"],
        "schedule_basis" => trigger["schedule_basis"],
        "due_ms" => c.time["utc_low_ms"] - 500,
        "late_window_ms" => 1000,
        "clock_generation" => c.time["clock_generation"],
        "time_zone_basis" => trigger["schedule_basis"]
      })

    c = %{c | event: due}
    {:ok, first} = F.advance(c)
    matched = satisfaction(c)

    time = %{
      c.time
      | "utc_low_ms" => c.time["utc_low_ms"] + 500,
        "utc_high_ms" => c.time["utc_high_ms"] + 500
    }

    assert {:ok, expired} = F.advance(%{matched | time: time}, first["run"])
    assert expired["outcome"] == "expired"
    assert expired["run"]["reason"] == "window_closed"
    assert expired["run"]["format"] == "wotex.routines.run@1"
    assert expired["proposals"] == []
    assert {:ok, completed} = F.advance(matched, first["run"])
    assert completed["run"]["window"] == first["run"]["window"]
  end

  defp fixture(options \\ []) do
    c = F.fixture(sensor: Keyword.get(options, :sensor, false))
    basis = hd(c.context["bases"])
    type = Keyword.get(options, :type, "boolean")

    value =
      case type do
        "integer" -> hd(c.corpus["bases"])["value"]
        "enum" -> %{"type" => "enum", "unit" => nil, "enum" => ["off", "on"]}
        "boolean" -> basis["value"]
      end

    basis = Keyword.get(options, :basis, &Function.identity/1).(%{basis | "value" => value})
    {:ok, digest} = Basis.semantic_digest(basis, c.limits)
    basis = %{basis | "semantic_digest" => digest}

    context = %{
      c.context
      | "bases" =>
          Enum.map(c.context["bases"], fn old ->
            if old["id"] == basis["id"], do: basis, else: old
          end),
        "registry" =>
          Enum.map(c.context["registry"], fn r ->
            if r["id"] == basis["id"], do: %{r | "semantic_digest" => digest}, else: r
          end)
    }

    context = put_in(context, ["bindings", "actuator", "basis", "semantic_digest"], digest)
    input = Keyword.get(options, :input, false)

    source =
      Map.merge(
        %{"steps" => Map.put(F.effect("apply"), "input", input)},
        Keyword.get(options, :source, %{})
      )

    F.compile(%{c | context: context}, source)
  end

  defp satisfaction(c, path \\ []) do
    basis = hd(c.context["bases"])
    node = c.source["steps"]
    input = if node["kind"] == "effect", do: node["input"], else: false

    fact =
      Map.merge(c.corpus["fact"], %{
        "id" => "current:1",
        "thing_id" => c.context["bindings"]["actuator"]["thing_id"],
        "affordance_name" => basis["affordance"]["name"],
        "value" => input,
        "unit" => basis["value"]["unit"],
        "profile_digest" => basis["semantic_digest"],
        "source_id" => "device:1"
      })

    snapshot =
      c.snapshot
      |> put_in(["facts", "actuator"], fact)
      |> put_in(["binding_bases", "actuator", "source_time_basis"], fact["source_time_basis"])

    event =
      Map.merge(Map.take(c.event, ~w(original program_digest)), %{
        "kind" => "satisfied",
        "path" => path,
        "ref" => "satisfied:1",
        "fact_id" => fact["id"],
        "report_contract" => basis["evidence"]["report_contract"]
      })

    %{c | event: event, snapshot: snapshot}
  end

  defp receipt(c, kind, path \\ []) do
    event = Map.merge(c.event, %{"kind" => kind, "path" => path, "ref" => kind <> ":1"})
    event = if kind == "admission", do: Map.put(event, "outcome", "held"), else: event
    %{c | event: event}
  end

  defp record(run, path), do: Enum.find(run["steps"], &(&1["path"] == path))

  defp schema(name) do
    :wotex_routines
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("schemas/" <> name <> ".schema.json")
    |> File.read!()
    |> JSON.decode!()
    |> ExJsonSchema.Schema.resolve()
  end
end
