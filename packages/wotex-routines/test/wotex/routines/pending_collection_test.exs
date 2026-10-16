Code.require_file("../../support/continuation_fixtures.exs", __DIR__)

defmodule Wotex.Routines.PendingCollectionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Arbitration, Collection, Error, Kernel, Model, Profile, Validation}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F

  test "a repeated complete cut retains deferred proposals and reserved contributors" do
    c = F.fixture()
    input = input(c, [{"a", false, "one"}, {"b", false, "two"}, {"c", false, "three"}])
    assert {:ok, first} = Collection.evaluate(input, c.profile, c.limits)
    assert first.data["format"] == "wotex.routines.collection@2"
    assert length(first.data["proposals"]) == 3
    assert Enum.map(first.data["proposal_states"], & &1["status"]) == ~w(proposed proposed proposed)
    assert {:ok, cut} = decide(c, first, 1)
    assert Enum.map(cut["decisions"], & &1["outcome"]) == ~w(selected batch-deferred batch-deferred)
    [[selected]] = cut["selected"]
    next = retained(first)

    next =
      update_in(next, ["entries"], fn entries ->
        Enum.map(entries, fn entry ->
          if entry["program"]["ir_digest"] == selected["program_digest"] do
            event =
              Map.merge(entry["event"], %{
                "kind" => "admission",
                "path" => selected["path"],
                "ref" => "charge:1",
                "outcome" => "held"
              })

            %{entry | "event" => event}
          else
            entry
          end
        end)
      end)

    assert {:ok, second} = Collection.evaluate(next, c.profile, c.limits)
    assert second.data["proposals"] == first.data["proposals"]
    assert Enum.count(second.data["proposal_states"], &(&1["status"] == "reserved")) == 1
    assert Enum.all?(second.data["transitions"], &(&1["result"]["proposals"] == []))
    assert {:ok, repeated} = decide(c, second, 1)
    assert repeated["selected"] == cut["selected"]

    assert Map.keys(repeated) |> Enum.sort() ==
             ~w(batch_limit collection_digest decisions dispositions selected)

    assert repeated["collection_digest"] == second.data["collection_digest"]

    assert Enum.all?(second.data["proposal_states"], fn state ->
             state["step_original"] in Enum.map(second.data["proposals"], & &1["step_original"])
           end)
  end

  test "nil and displaced events cannot conceal a supplied live run" do
    c = F.fixture()
    assert {:ok, first} = Collection.evaluate(input(c, [{"a", false, "one"}]), c.profile, c.limits)
    next = retained(first)
    [entry] = next["entries"]
    run = entry["prior"]["original"]

    for bad <- [
          %{entry | "event" => nil},
          %{entry | "event" => %{entry["event"] | "original" => "other"}},
          %{
            entry
            | "event" => nil,
              "prior" => %{entry["prior"] | "original" => nil, "busy" => run}
          },
          %{entry | "prior" => %{entry["prior"] | "original" => nil, "busy" => run}}
        ] do
      assert {:error, %Error{code: :incomplete_run_continuation}} =
               Collection.evaluate(%{next | "entries" => [bad]}, c.profile, c.limits)
    end

    equal = put_in(entry, ["prior", "busy"], run)
    assert {:ok, current} = Collection.evaluate(%{next | "entries" => [equal]}, c.profile, c.limits)
    assert current.data["proposals"] == first.data["proposals"]
  end

  test "v1 retains its exact input and newly emitted-only output" do
    c = F.fixture()
    legacy = Map.delete(input(c, [{"a", false, "one"}]), "format")
    assert {:ok, first} = Collection.evaluate(legacy, c.profile, c.limits)
    assert first.data["format"] == "wotex.routines.collection@1"
    refute Map.has_key?(first.data, "proposal_states")
    assert length(first.data["proposals"]) == 1
    next = retained(first)
    assert {:ok, second} = Collection.evaluate(next, c.profile, c.limits)
    assert second.data["proposals"] == []

    assert {:ok, idle} =
             Collection.evaluate(
               put_in(next, ["entries", Access.at(0), "event"], nil),
               c.profile,
               c.limits
             )

    assert hd(idle.data["transitions"])["result"] == nil

    assert {:error, %Error{}} =
             Collection.evaluate(
               Map.put(legacy, "format", "wotex.routines.collection-input@1"),
               c.profile,
               c.limits
             )
  end

  test "reserved equivalents coalesce with every original and keep their first charge" do
    c = F.fixture()

    {:ok, first} =
      Collection.evaluate(input(c, [{"a", false, "one"}, {"b", false, "one"}]), c.profile, c.limits)

    next = retained(first)

    next =
      put_in(next, ["entries", Access.at(0), "event"], receipt(hd(next["entries"]), "admission"))

    assert {:ok, held} = Collection.evaluate(next, c.profile, c.limits)
    assert {:ok, result} = decide(c, held, 1)
    assert [contributors] = result["selected"]
    assert Enum.sort(Enum.map(contributors, & &1["original"])) == ~w(original:a original:b)

    assert Enum.sort(Enum.map(held.data["proposal_states"], & &1["status"])) ==
             ~w(proposed reserved)

    assert {:ok, repeated} = Collection.evaluate(retained(held), c.profile, c.limits)
    assert repeated.data["proposals"] == held.data["proposals"]

    assert Enum.map(repeated.data["transitions"], & &1["result"]["run"]["spent"]) ==
             Enum.map(held.data["transitions"], & &1["result"]["run"]["spent"])
  end

  test "a retained conflict in the last supplied member participates before batching" do
    c = F.fixture()

    {:ok, first} =
      Collection.evaluate(
        input(c, [{"a", false, "shared"}, {"b", false, "other"}, {"c", true, "shared"}]),
        c.profile,
        c.limits
      )

    assert {:ok, current} = Collection.evaluate(retained(first), c.profile, c.limits)
    assert Enum.all?(current.data["transitions"], &(&1["result"]["proposals"] == []))
    assert {:ok, result} = decide(c, current, 1)
    assert [[%{"original" => "original:b"}]] = result["selected"]

    assert Enum.sort(Enum.map(result["decisions"], & &1["outcome"])) ==
             ~w(conflict conflict selected)
  end

  test "64 sixteen-effect members retain all 1024 pending identities before a 16-group cutoff" do
    c = F.fixture()

    parallel = %{
      "id" => "all",
      "kind" => "parallel",
      "branches" =>
        Enum.map(0..3, fn group ->
          %{
            "id" => "group:#{group}",
            "kind" => "parallel",
            "branches" => Enum.map(0..3, &F.effect("effect:#{group}:#{&1}"))
          }
        end)
    }

    definitions = Enum.map(1..64, &{"member:#{&1}", false, "target:#{&1}"})
    input = input(c, definitions, %{"steps" => parallel})
    assert {:ok, first} = Collection.evaluate(input, c.profile, c.limits)
    assert length(first.data["proposals"]) == 1024
    assert length(first.data["proposal_states"]) == 1024
    assert {:ok, second} = Collection.evaluate(retained(first), c.profile, c.limits)
    assert second.data["proposals"] == first.data["proposals"]
    assert second.data["proposal_states"] == first.data["proposal_states"]
    assert {:ok, result} = decide(c, second, 16)
    assert length(result["selected"]) == 16
    assert Enum.count(result["decisions"], &(&1["outcome"] == "batch-deferred")) == 48 * 16
    {:ok, narrow} = Profile.new(%{c.profile.data | "pending_work" => 1023})
    narrower = %{c | profile: narrow}
    narrow_input = input(narrower, definitions, %{"steps" => parallel})

    narrow_input =
      update_in(narrow_input, ["entries"], fn entries ->
        Enum.map(entries, fn entry ->
          {:ok, started} = kernel(narrower, entry, narrow_input["time"])
          event = Map.put(entry["event"], "kind", "resume")
          %{entry | "event" => event, "prior" => %{entry["prior"] | "original" => started["run"]}}
        end)
      end)

    assert {:error, %Error{code: :pending_work_bound}} =
             Collection.evaluate(narrow_input, narrow, c.limits)

    assert {:error, %Error{code: :pending_work_bound}} =
             Arbitration.decide(
               %Collection{data: %{second.data | "input" => narrow_input}},
               %{},
               16,
               narrow,
               c.limits
             )
  end

  test "full regeneration refuses altered, missing or duplicated proposals and state records" do
    c = F.fixture()

    {:ok, collection} =
      Collection.evaluate(input(c, [{"a", false, "one"}, {"b", false, "two"}]), c.profile, c.limits)

    data = collection.data
    assert {:ok, ^data} = Collection.to_map(collection, c.profile, c.limits)

    for changed <- [
          %{data | "proposals" => tl(data["proposals"])},
          %{data | "proposals" => [hd(data["proposals"]), hd(data["proposals"])]},
          put_in(data, ["proposals", Access.at(0), "input"], true),
          put_in(data, ["proposal_states", Access.at(0), "status"], "reserved"),
          %{data | "proposal_states" => Enum.reverse(data["proposal_states"])},
          %{data | "proposal_states" => []},
          Map.delete(data, "proposal_states"),
          Map.put(data, "extra", true)
        ] do
      {:ok, digest} = Validation.hash(Map.delete(changed, "collection_digest"), c.limits)
      changed = Map.put(changed, "collection_digest", digest)
      assert {:error, %Error{}} = Collection.to_map(changed, c.profile, c.limits)
      assert {:error, %Error{}} = Collection.to_map(%Collection{data: changed}, c.profile, c.limits)

      assert {:error, %Error{}} =
               Arbitration.decide(%Collection{data: changed}, %{}, 1, c.profile, c.limits)
    end
  end

  test "terminal or absent idle entries have no transition and malformed events still refuse" do
    c = F.fixture()
    initial = input(c, [{"a", false, "one"}])

    assert {:ok, idle} =
             Collection.evaluate(
               put_in(initial, ["entries", Access.at(0), "event"], nil),
               c.profile,
               c.limits
             )

    assert idle.data["proposals"] == []
    {:ok, first} = Collection.evaluate(initial, c.profile, c.limits)
    next = retained(first)
    entry = hd(next["entries"])
    cancel = Map.put(entry["event"], "kind", "cancel")

    {:ok, stopped} =
      Collection.evaluate(
        put_in(next, ["entries", Access.at(0), "event"], cancel),
        c.profile,
        c.limits
      )

    assert {:ok, terminal} =
             Collection.evaluate(
               put_in(retained(stopped), ["entries", Access.at(0), "event"], nil),
               c.profile,
               c.limits
             )

    assert hd(terminal.data["transitions"])["result"] == nil
    assert terminal.data["proposals"] == []
    assert terminal.data["proposal_states"] == []

    for event <- [17, %{}, Map.put(entry["event"], "extra", true)] do
      assert {:error, %Error{}} =
               Collection.evaluate(
                 put_in(next, ["entries", Access.at(0), "event"], event),
                 c.profile,
                 c.limits
               )
    end
  end

  test "a distinct busy run cannot be displaced or hidden by terminal original history" do
    c = F.fixture()
    initial = input(c, [{"a", false, "one"}])
    [entry] = initial["entries"]
    {:ok, original} = kernel(c, entry, initial["time"])
    incoming = %{entry | "event" => %{entry["event"] | "original" => "original:other"}}
    {:ok, other} = kernel(c, incoming, initial["time"])

    entry = %{
      entry
      | "prior" => %{entry["prior"] | "original" => original["run"], "busy" => other["run"]}
    }

    assert {:error, %Error{code: :incomplete_run_continuation}} =
             Collection.evaluate(%{initial | "entries" => [entry]}, c.profile, c.limits)

    cancelled = %{
      incoming
      | "event" => %{incoming["event"] | "kind" => "cancel"},
        "prior" => %{incoming["prior"] | "original" => other["run"]}
    }

    {:ok, stopped} = kernel(c, cancelled, initial["time"])

    entry = %{
      entry
      | "event" => nil,
        "prior" => %{entry["prior"] | "original" => stopped["run"], "busy" => original["run"]}
    }

    assert {:error, %Error{code: :incomplete_run_continuation}} =
             Collection.evaluate(%{initial | "entries" => [entry]}, c.profile, c.limits)
  end

  test "handed-off and expired pending steps are excluded while charges remain retained" do
    c = F.fixture()

    {:ok, first} =
      Collection.evaluate(
        input(c, [{"a", false, "one"}], %{"run_ms" => 20_000}),
        c.profile,
        c.limits
      )

    next = retained(first)

    next =
      put_in(next, ["entries", Access.at(0), "event"], receipt(hd(next["entries"]), "admission"))

    {:ok, held} = Collection.evaluate(next, c.profile, c.limits)

    for {event_kind, time, outcome} <- [{"handoff", 20, "running"}, {"resume", 15_020, "expired"}] do
      current = retained(held)

      current =
        if event_kind == "handoff",
          do:
            put_in(
              current,
              ["entries", Access.at(0), "event"],
              receipt(hd(current["entries"]), "handoff")
            ),
          else: current

      current = put_in(current, ["time", "elapsed_ms"], time)
      assert {:ok, result} = Collection.evaluate(current, c.profile, c.limits)
      assert result.data["proposals"] == []
      assert result.data["proposal_states"] == []
      assert hd(result.data["transitions"])["result"]["outcome"] == outcome

      assert hd(result.data["transitions"])["result"]["run"]["spent"] ==
               hd(held.data["transitions"])["result"]["run"]["spent"]
    end
  end

  test "current root and invoked conditions remove and restore retained pending work" do
    for mode <- [:root, :invoke] do
      c = F.fixture(sensor: true)
      condition = %{"op" => "gt", "binding" => "sensor", "value" => 2000}

      c =
        if mode == :root do
          F.compile(c, %{"condition" => condition})
        else
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
        end

      sample = F.sample(c, 1, 20, 3000)
      entry = entry(%{c | snapshot: sample.snapshot})
      initial = membership(c, [entry])
      {:ok, first} = Collection.evaluate(initial, c.profile, c.limits)
      assert length(first.data["proposals"]) == 1

      for fact <- [nil, %{sample.snapshot["facts"]["sensor"] | "value" => 1000}] do
        next =
          put_in(retained(first), ["entries", Access.at(0), "snapshot", "facts", "sensor"], fact)

        assert {:ok, blocked} = Collection.evaluate(next, c.profile, c.limits)
        assert blocked.data["proposals"] == []
        assert blocked.data["proposal_states"] == []

        restored =
          put_in(
            retained(blocked),
            ["entries", Access.at(0), "snapshot", "facts", "sensor"],
            sample.snapshot["facts"]["sensor"]
          )

        assert {:ok, ready} = Collection.evaluate(restored, c.profile, c.limits)
        assert ready.data["proposals"] == first.data["proposals"]
        assert hd(ready.data["transitions"])["result"]["proposals"] == []
      end

      if mode == :invoke do
        expired = put_in(retained(first), ["time", "elapsed_ms"], 120)
        assert {:ok, expired} = Collection.evaluate(expired, c.profile, c.limits)
        assert expired.data["proposals"] == []
        assert hd(expired.data["transitions"])["result"]["outcome"] == "expired"
      end
    end
  end

  test "conditional selection stays fixed when the current predicate changes" do
    c = F.fixture(sensor: true)

    steps = %{
      "id" => "choice",
      "kind" => "if",
      "condition" => %{"op" => "gt", "binding" => "sensor", "value" => 2000},
      "then" => F.effect("yes"),
      "else" => F.effect("no", true)
    }

    c = F.compile(c, %{"steps" => steps})
    sample = F.sample(c, 1, 20, 3000)

    {:ok, first} =
      Collection.evaluate(
        membership(c, [entry(%{c | snapshot: sample.snapshot})]),
        c.profile,
        c.limits
      )

    next =
      put_in(
        retained(first),
        ["entries", Access.at(0), "snapshot", "facts", "sensor", "value"],
        1000
      )

    assert {:ok, current} = Collection.evaluate(next, c.profile, c.limits)
    assert current.data["proposals"] == first.data["proposals"]
    assert [%{"path" => [0], "input" => false}] = current.data["proposals"]
  end

  test "a satisfied branch disappears while another retained branch stays eligible" do
    c = F.fixture()

    steps = %{
      "id" => "parallel",
      "kind" => "parallel",
      "branches" => [F.effect("left"), F.effect("right")]
    }

    {:ok, first} =
      Collection.evaluate(input(c, [{"a", false, "one"}], %{"steps" => steps}), c.profile, c.limits)

    next = retained(first)
    [entry] = next["entries"]
    basis = hd(entry["program"]["context"]["bases"])

    fact =
      Map.merge(c.corpus["fact"], %{
        "id" => "current:1",
        "thing_id" => "urn:pending:one",
        "affordance_name" => "fast",
        "value" => false,
        "unit" => nil,
        "source_id" => "device:1",
        "profile_digest" => basis["semantic_digest"]
      })

    snapshot =
      entry["snapshot"]
      |> put_in(["facts", "actuator"], fact)
      |> put_in(["binding_bases", "actuator", "source_time_basis"], fact["source_time_basis"])

    event =
      Map.merge(entry["event"], %{
        "kind" => "satisfied",
        "path" => [0],
        "ref" => "satisfied:1",
        "fact_id" => fact["id"],
        "report_contract" => basis["evidence"]["report_contract"]
      })

    next = %{next | "entries" => [%{entry | "event" => event, "snapshot" => snapshot}]}
    assert {:ok, current} = Collection.evaluate(next, c.profile, c.limits)
    assert [%{"path" => [1]}] = current.data["proposals"]
    assert [%{"status" => "proposed"}] = current.data["proposal_states"]
    assert hd(current.data["transitions"])["result"]["proposals"] == []
    assert hd(current.data["transitions"])["result"]["run"]["spent"] == []
  end

  test "full membership, shared snapshot, active-run bounds and closed schemas still apply" do
    c = F.fixture()
    initial = input(c, [{"a", false, "one"}, {"b", false, "one"}])
    [left, right] = initial["entries"]

    for bad <- [
          %{initial | "entries" => [left]},
          %{initial | "entries" => [left, left]},
          %{initial | "entries" => [left, put_in(right, ["snapshot", "id"], "different")]},
          %{
            initial
            | "entries" => [
                left,
                put_in(right, ["snapshot", "resource_revisions", "resource:one"], 2)
              ]
          },
          %{
            initial
            | "entries" => [
                left,
                put_in(right, ["snapshot", "binding_bases", "actuator", "source_epoch"], "other")
              ]
          },
          Map.put(initial, "extra", true),
          %{initial | "format" => "unknown"}
        ] do
      assert {:error, %Error{}} = Collection.evaluate(bad, c.profile, c.limits)
    end

    {:ok, profile} = Profile.new(%{c.profile.data | "active_runs" => 1})
    limited = %{c | profile: profile}

    assert {:error, %Error{code: :active_run_bound}} =
             Collection.evaluate(
               input(limited, [{"a", false, "one"}, {"b", false, "two"}]),
               profile,
               c.limits
             )

    {:ok, collection} = Collection.evaluate(initial, c.profile, c.limits)
    {:ok, decision} = decide(c, collection, 1)

    for schema_name <- ~w(wro-02-continuation wro-02-collection) do
      schema = schema(schema_name)

      for data <- [initial, collection.data, decision],
          do: assert(:ok = ExJsonSchema.Validator.validate(schema, data))
    end

    assert {:ok, reversed} =
             Collection.evaluate(
               %{initial | "entries" => Enum.reverse(initial["entries"])},
               c.profile,
               c.limits
             )

    assert reversed.data["proposals"] == collection.data["proposals"]
    assert reversed.data["proposal_states"] == collection.data["proposal_states"]
    assert reversed.data["transitions"] == collection.data["transitions"]
  end

  test "an empty explicit set stays closed and does not discover omitted host membership" do
    c = F.fixture()
    assert {:ok, collection} = Collection.evaluate(input(c, []), c.profile, c.limits)
    assert collection.data["transitions"] == []
    assert collection.data["proposals"] == []
    assert collection.data["proposal_states"] == []
    assert {:ok, decision} = decide(c, collection, 1)
    assert decision["selected"] == []
    assert decision["decisions"] == []
  end

  test "frozen staged models refuse a request to include complete pending arbitration" do
    c = F.fixture() |> F.compile()

    scope =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-04-receipt-prefix.json")
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("scope")

    scope = %{scope | "environment" => "manual_receipts_complete_pending_arbitration"}

    assert {:error, %Error{code: :unsupported_model_scope}} =
             Model.compile(c.program, scope, c.profile, c.limits)
  end

  defp input(c, definitions, changes \\ %{}) do
    entries =
      Enum.map(definitions, fn {id, value, target} ->
        context =
          c.context
          |> put_in(["bindings", "actuator", "thing_id"], "urn:pending:" <> target)
          |> put_in(["bindings", "actuator", "resource_roles", "target"], "resource:" <> target)

        member =
          F.compile(
            %{c | context: context},
            Map.merge(%{"id" => id, "steps" => F.effect("apply", value)}, changes)
          )

        %{
          "program" => member.program.data,
          "event" => %{member.event | "original" => "original:" <> id},
          "snapshot" => member.snapshot,
          "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
        }
      end)

    membership(c, entries)
  end

  defp membership(c, entries) do
    programs = Enum.map(entries, & &1["program"]["ir_digest"])

    %{
      "format" => "wotex.routines.collection-input@2",
      "time" => c.time,
      "membership" => %{"generation" => "membership:1", "programs" => programs},
      "entries" => Enum.map(entries, &put_in(&1, ["snapshot", "active_programs"], programs))
    }
  end

  defp retained(collection) do
    runs = Map.new(collection.data["transitions"], &{&1["program_digest"], &1["result"]["run"]})

    update_in(collection.data["input"], ["entries"], fn entries ->
      Enum.map(entries, fn entry ->
        run = runs[entry["program"]["ir_digest"]]

        event = %{
          "kind" => "resume",
          "original" => run["original"],
          "program_digest" => run["program_digest"]
        }

        %{entry | "event" => event, "prior" => %{entry["prior"] | "original" => run}}
      end)
    end)
  end

  defp decide(c, collection, batch) do
    dispositions =
      Map.new(
        collection.data["proposals"],
        &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      )

    Arbitration.decide(collection, dispositions, batch, c.profile, c.limits)
  end

  defp receipt(entry, kind) do
    event =
      Map.merge(Map.take(entry["event"], ~w(original program_digest)), %{
        "kind" => kind,
        "path" => [],
        "ref" => kind <> ":1"
      })

    if kind == "admission", do: Map.put(event, "outcome", "held"), else: event
  end

  defp kernel(c, entry, time),
    do:
      Kernel.advance(
        entry["program"],
        entry["event"],
        entry["snapshot"],
        time,
        entry["prior"],
        c.profile,
        c.limits
      )

  defp entry(c),
    do: %{
      "program" => c.program.data,
      "event" => c.event,
      "snapshot" => c.snapshot,
      "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
    }

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
