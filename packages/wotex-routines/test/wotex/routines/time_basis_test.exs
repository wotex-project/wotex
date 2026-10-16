Code.require_file("../../support/continuation_fixtures.exs", __DIR__)

defmodule Wotex.Routines.TimeBasisTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Basis, Collection, Edge, Error, Run, Schedule, Temporal, Time, Witness}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F

  test "Time preserves both closed grammars and requires paired explicit UTC qualification" do
    c = F.fixture()
    time = time2(c.time)
    {:ok, native} = Time.new(time, c.limits)
    assert {:ok, ^time} = Time.to_map(native, c.limits)
    assert Time.to_map(c.time, c.limits) == {:ok, c.time}
    absent = absent_utc(time)
    assert {:ok, ^absent} = Time.to_map(absent, c.limits)

    invalid = [
      %{time | "utc_generation" => nil},
      %{time | "utc_generation" => ""},
      %{absent | "utc_generation" => "utc:1"},
      %{time | "utc_low_ms" => nil},
      %{time | "utc_high_ms" => time["utc_low_ms"] - 1},
      %{time | "elapsed_ms" => -1},
      %{time | "format" => "wotex.routines.time@3"},
      Map.put(time, "assume_utc", true),
      Map.put(c.time, "utc_generation", nil),
      Map.put(native, :extra, true)
    ]

    for value <- invalid, do: assert({:error, %Error{}} = Time.new(value, c.limits))

    for key <- Map.keys(time),
        do: assert({:error, %Error{}} = Time.new(Map.delete(time, key), c.limits))
  end

  test "Run@2 retains the selected time grammar and preserves legacy originals and slots" do
    c = F.fixture() |> F.compile()
    {:ok, legacy} = F.advance(c)
    current = %{c | time: time2(c.time)}
    {:ok, new} = F.advance(current)
    run = new["run"]
    assert run["format"] == "wotex.routines.run@2"
    assert run["time_format"] == "wotex.routines.time@2"
    assert Enum.all?(run["steps"], &Map.has_key?(&1["receipts"], "satisfied"))
    assert Enum.all?(run["steps"], &is_nil(&1["receipts"]["satisfied"]))
    assert new["basis"]["time"] == current.time
    assert Run.to_map(run, c.program, c.profile, c.limits) == {:ok, run}
    assert Run.to_map(legacy["run"], c.program, c.profile, c.limits) == {:ok, legacy["run"]}

    stripped =
      run
      |> Map.drop(~w(format time_format))
      |> Map.update!("steps", fn steps ->
        Enum.map(
          steps,
          &update_in(&1, ["receipts"], fn receipts -> Map.delete(receipts, "satisfied") end)
        )
      end)

    assert stripped == Map.delete(legacy["run"], "format")

    for invalid <- [
          Map.put(legacy["run"], "time_format", "wotex.routines.time@1"),
          Map.delete(run, "time_format"),
          %{run | "time_format" => "wotex.routines.time@3"},
          update_in(run, ["steps", Access.at(0), "receipts"], &Map.delete(&1, "satisfied")),
          put_in(run, ["steps", Access.at(0), "receipts", "satisfied"], %{
            "ref" => "unearned",
            "digest" => digest(),
            "outcome" => "matched"
          })
        ] do
      assert {:error, %Error{}} = Run.new(invalid, c.program, c.profile, c.limits)
    end
  end

  test "grammar switches refuse before continuing live or terminal history" do
    for steps <- [F.delayed_effect(), %{"id" => "done", "kind" => "noop"}] do
      c = F.fixture() |> F.compile(%{"steps" => steps})
      {:ok, legacy} = F.advance(c)
      current = %{c | time: time2(c.time)}
      {:ok, new} = F.advance(current)

      assert {:error, %Error{code: :clock_format_mismatch}} =
               F.advance(F.resume(current), legacy["run"])

      assert {:error, %Error{code: :clock_format_mismatch}} = F.advance(F.resume(c), new["run"])
    end
  end

  test "one shared clock separates manual, countdown and UTC-window continuation" do
    c = F.fixture()

    for format <- [nil, "wotex.routines.collection-input@2"] do
      {input, programs} = shared_collection(c)
      input = if format, do: Map.put(input, "format", format), else: input
      {:ok, initial} = Collection.evaluate(input, c.profile, c.limits)

      assert Enum.all?(
               initial.data["transitions"],
               &(&1["result"]["run"]["format"] == "wotex.routines.run@2")
             )

      resumed = resume_collection(initial.data)

      corrected = %{
        resumed["time"]
        | "elapsed_ms" => 120,
          "utc_generation" => "utc:2",
          "utc_low_ms" => 1100,
          "utc_high_ms" => 1100
      }

      {:ok, changed} = Collection.evaluate(%{resumed | "time" => corrected}, c.profile, c.limits)
      results = results(changed.data)
      assert length(results["manual"]["proposals"]) == 1
      assert length(results["countdown"]["proposals"]) == 1
      assert results["utc"]["outcome"] == "expired"
      assert results["utc"]["run"]["reason"] == "clock_changed"
      assert results["utc"]["proposals"] == []

      if format do
        {:ok, repeated} = Collection.evaluate(resume_collection(changed.data), c.profile, c.limits)
        assert repeated.data["proposals"] == changed.data["proposals"]
        assert repeated.data["proposal_states"] == changed.data["proposal_states"]
        assert Enum.all?(repeated.data["transitions"], &(&1["result"]["proposals"] == []))
      end

      for result <- Map.values(results) do
        assert result["basis"]["time"] == corrected
        assert result["run"]["clock_generation"] == "elapsed:1"
      end

      {:ok, missing} =
        Collection.evaluate(%{resumed | "time" => absent_utc(corrected)}, c.profile, c.limits)

      results = results(missing.data)
      assert length(results["manual"]["proposals"]) == 1
      assert length(results["countdown"]["proposals"]) == 1
      assert results["utc"]["run"]["reason"] == "window_closed"
      assert missing.data["input"]["membership"]["programs"] == programs

      for changed_time <- [
            %{corrected | "epoch" => "boot:2"},
            %{corrected | "clock_generation" => "elapsed:2"}
          ] do
        {:ok, expired} =
          Collection.evaluate(%{resumed | "time" => changed_time}, c.profile, c.limits)

        for result <- Map.values(results(expired.data)) do
          assert result["outcome"] == "expired"
          assert result["run"]["reason"] == "clock_changed"
          assert result["proposals"] == []
        end
      end
    end
  end

  test "UTC-window confidence, expiry precedence and immutable descriptors stay distinct" do
    c = F.fixture()
    {input, _} = shared_collection(c)
    {:ok, initial} = Collection.evaluate(input, c.profile, c.limits)
    resumed = resume_collection(initial.data)

    for {time, expected} <- [
          {%{input["time"] | "utc_high_ms" => 1500}, "window_closed"},
          {%{input["time"] | "utc_low_ms" => 999}, "window_closed"},
          {%{input["time"] | "elapsed_ms" => 19, "utc_generation" => "utc:2"}, "clock_regressed"},
          {%{input["time"] | "elapsed_ms" => 1020, "utc_generation" => "utc:2"}, "deadline_elapsed"}
        ] do
      {:ok, collection} = Collection.evaluate(%{resumed | "time" => time}, c.profile, c.limits)
      result = results(collection.data)["utc"]
      assert result["run"]["reason"] == expected
      assert result["run"]["window"]["clock_generation"] == "utc:1"
      assert result["run"]["window"]["due_ms"] == 1000
      assert result["proposals"] == []
    end
  end

  test "Edge@2 keeps elapsed qualification across UTC changes and resets across grammars" do
    c = elapsed_sensor()

    trigger = %{
      "kind" => "edge",
      "binding" => "sensor",
      "direction" => "rising",
      "debounce_ms" => 100,
      "cooldown_ms" => 200,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    c = F.compile(c, %{"trigger" => trigger})
    first = F.sample(c, 1, 20, 1000)
    {:ok, legacy} = edge(first, nil)
    current = %{first | time: time2(first.time)}
    {:ok, baseline} = edge(current, nil)
    assert baseline["edge"]["format"] == "wotex.routines.edge@2"
    assert baseline["edge"]["time_format"] == "wotex.routines.time@2"
    assert Edge.to_map(baseline["edge"], c.program, c.profile, c.limits) == {:ok, baseline["edge"]}

    next = F.sample(c, 2, 30, 3000)
    {:ok, candidate} = edge(%{next | time: time2(next.time)}, baseline["edge"])
    ready = F.sample(c, 3, 130, 3000)
    ready = %{ready | time: absent_utc(time2(ready.time))}
    {:ok, qualified} = edge(ready, candidate["edge"])
    assert qualified["eligible"]
    assert qualified["edge"]["cooldown_until_ms"] == 330
    assert qualified["edge"]["clock_generation"] == "elapsed:1"

    {:ok, switched} = edge(%{next | time: time2(next.time)}, legacy["edge"])
    refute switched["eligible"]
    assert switched["reason"] == "baseline"
    assert switched["edge"]["candidate_since_ms"] == nil
    {:ok, reverse} = edge(F.sample(c, 4, 140, 1000), qualified["edge"])
    refute reverse["eligible"]
    assert reverse["reason"] == "baseline"
    refute Map.has_key?(reverse["edge"], "time_format")
  end

  test "required source UTC age still makes an edge unknown when confidence disappears" do
    c = F.fixture(sensor: true)

    trigger = %{
      "kind" => "edge",
      "binding" => "sensor",
      "direction" => "rising",
      "debounce_ms" => 0,
      "cooldown_ms" => 0,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    c = F.compile(c, %{"trigger" => trigger})
    sample = F.sample(c, 1, 20, 1000)
    {:ok, baseline} = edge(%{sample | time: time2(sample.time)}, nil)
    next = F.sample(c, 2, 30, 3000)
    {:ok, unknown} = edge(%{next | time: absent_utc(time2(next.time))}, baseline["edge"])
    refute unknown["eligible"]
    assert unknown["reason"] == "unqualified"
    assert unknown["edge"]["baseline"] == nil
  end

  test "scalar UTC projection binds its grammar and UTC generation without changing originals" do
    c = F.fixture()
    schedule = schedule(c, "interval", %{"first_due_ms" => 1000, "period_ms" => 1000})
    query = %{"from_ms" => 0, "until_ms" => 4000, "limit" => 1}
    legacy_time = %{c.time | "clock_generation" => "utc:1"}
    current = time2(c.time)
    {:ok, old} = Temporal.page(schedule, query, legacy_time, nil, c.limits)
    {:ok, new} = Temporal.page(schedule, query, current, nil, c.limits)
    one = hd(new["occurrences"])
    assert one["original"] == hd(old["occurrences"])["original"]
    assert one["event"]["clock_generation"] == "utc:1"
    assert one["time_format"] == "wotex.routines.time@2"
    assert Map.keys(hd(old["occurrences"])) |> Enum.sort() == ~w(due_ms event ordinal original)
    assert new["next_cursor"] != old["next_cursor"]

    assert {:error, %Error{code: :stale_temporal_cursor}} =
             Temporal.page(schedule, query, current, old["next_cursor"], c.limits)

    assert {:error, %Error{code: :stale_temporal_cursor}} =
             Temporal.page(schedule, query, legacy_time, new["next_cursor"], c.limits)

    assert {:ok, _} =
             Temporal.page(
               schedule,
               query,
               %{current | "clock_generation" => "elapsed:2"},
               new["next_cursor"],
               c.limits
             )

    assert {:error, %Error{code: :stale_temporal_cursor}} =
             Temporal.page(
               schedule,
               query,
               %{current | "utc_generation" => "utc:2"},
               new["next_cursor"],
               c.limits
             )

    assert {:error, %Error{code: :missing_utc_basis}} =
             Temporal.page(schedule, query, absent_utc(current), nil, c.limits)

    c =
      F.compile(c, %{
        "trigger" => %{
          "kind" => "due",
          "schedule_id" => schedule.data["schedule_id"],
          "schedule_basis" => schedule.data["definition_digest"]
        }
      })

    assert {:ok, _} = Temporal.event(schedule, one, c.program, current, c.profile, c.limits)

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Temporal.event(schedule, one, c.program, legacy_time, c.profile, c.limits)

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Temporal.event(
               schedule,
               hd(old["occurrences"]),
               c.program,
               current,
               c.profile,
               c.limits
             )
  end

  test "countdown scalar projection remains elapsed-only with absent UTC confidence" do
    c = F.fixture()

    schedule =
      schedule(c, "countdown", %{
        "due_elapsed_ms" => 100,
        "epoch" => c.time["epoch"],
        "clock_generation" => c.time["clock_generation"]
      })

    current = absent_utc(time2(c.time))
    query = %{"from_ms" => 0, "until_ms" => 200, "limit" => 1}
    {:ok, page} = Temporal.page(schedule, query, current, nil, c.limits)
    one = hd(page["occurrences"])
    assert one["event"]["clock_generation"] == "elapsed:1"
    assert one["event"]["due_elapsed_ms"] == 100

    c =
      F.compile(c, %{
        "trigger" => %{
          "kind" => "countdown",
          "schedule_id" => schedule.data["schedule_id"],
          "schedule_basis" => schedule.data["definition_digest"]
        }
      })

    assert {:ok, _} = Temporal.event(schedule, one, c.program, current, c.profile, c.limits)

    assert {:error, %Error{code: :changed_time_basis}} =
             Temporal.page(
               schedule,
               query,
               %{current | "clock_generation" => "elapsed:2"},
               nil,
               c.limits
             )
  end

  test "concrete Witness frames retain the complete independent time basis" do
    c = F.fixture() |> F.compile(%{"steps" => F.delayed_effect()})
    current = time2(c.time)

    frames = [
      %{"event" => c.event, "snapshot" => c.snapshot, "time" => current},
      %{
        "event" => F.resume(c).event,
        "snapshot" => c.snapshot,
        "time" => %{current | "elapsed_ms" => 120, "utc_generation" => "utc:2"}
      }
    ]

    witness = %{
      "format" => "wotex.routines.witness@1",
      "property" => "proposal_once",
      "program_digest" => c.program.data["ir_digest"],
      "source_digest" => c.program.data["source_digest"],
      "compiler_basis" => c.context["compiler_basis"],
      "max_steps" => 2,
      "max_originals" => 1,
      "initial" => %{"runs" => [], "edge" => nil},
      "frames" => frames
    }

    {:ok, replay} = Witness.replay(c.program, witness, c.profile, c.limits)
    refute replay["reproduced"]
    assert Enum.map(replay["transitions"], & &1["basis"]["time"]) == Enum.map(frames, & &1["time"])
    assert Enum.all?(replay["transitions"], &(&1["run"]["format"] == "wotex.routines.run@2"))
  end

  defp time2(time),
    do: Map.merge(time, %{"format" => "wotex.routines.time@2", "utc_generation" => "utc:1"})

  defp absent_utc(time),
    do: %{time | "utc_generation" => nil, "utc_low_ms" => nil, "utc_high_ms" => nil}

  defp digest, do: "sha256:" <> String.duplicate("6", 64)

  defp edge(c, prior),
    do: Edge.advance(c.program, c.event, c.snapshot, c.time, prior, c.profile, c.limits)

  defp elapsed_sensor do
    c = F.fixture(sensor: true)
    original = hd(c.corpus["bases"])
    basis = put_in(original, ["evidence", "require_source_time"], false)
    {:ok, hash} = Basis.semantic_digest(basis, c.limits)
    basis = %{basis | "semantic_digest" => hash}
    context = c.context

    context = %{
      context
      | "bases" => Enum.map(context["bases"], &if(&1["id"] == basis["id"], do: basis, else: &1)),
        "registry" =>
          Enum.map(
            context["registry"],
            &if(&1["id"] == basis["id"], do: Map.put(&1, "semantic_digest", hash), else: &1)
          )
    }

    context = put_in(context, ["bindings", "sensor", "basis", "semantic_digest"], hash)
    %{c | context: context, corpus: put_in(c.corpus, ["fact", "profile_digest"], hash)}
  end

  defp schedule(c, kind, fields) do
    data =
      Map.merge(
        %{
          "format" => "wotex.routines.schedule@1",
          "kind" => kind,
          "schedule_id" => "schedule:1",
          "late_window_ms" => 500,
          "time_basis" => digest()
        },
        fields
      )

    {:ok, digest} = Schedule.semantic_digest(data, c.limits)
    {:ok, schedule} = Schedule.new(Map.put(data, "definition_digest", digest), c.limits)
    schedule
  end

  defp shared_collection(c) do
    time = %{time2(c.time) | "utc_low_ms" => 1000, "utc_high_ms" => 1000}

    members =
      Enum.map(["manual", "countdown", "utc"], fn name ->
        trigger =
          if name == "manual",
            do: %{"kind" => "manual"},
            else: %{
              "kind" => if(name == "utc", do: "due", else: "countdown"),
              "schedule_id" => name,
              "schedule_basis" => digest()
            }

        member = F.compile(c, %{"id" => name, "trigger" => trigger, "steps" => F.delayed_effect()})
        event = %{member.event | "original" => name}

        event =
          case name do
            "manual" ->
              event

            "utc" ->
              Map.merge(event, %{
                "kind" => "due",
                "schedule_id" => name,
                "schedule_basis" => digest(),
                "due_ms" => 1000,
                "late_window_ms" => 500,
                "clock_generation" => "utc:1",
                "time_zone_basis" => digest()
              })

            "countdown" ->
              Map.merge(event, %{
                "kind" => "elapsed_due",
                "schedule_id" => name,
                "schedule_basis" => digest(),
                "due_elapsed_ms" => 20,
                "late_window_ms" => 500,
                "clock_generation" => "elapsed:1",
                "epoch" => time["epoch"],
                "time_basis" => digest()
              })
          end

        %{member | event: event}
      end)

    programs = Enum.map(members, & &1.program.data["ir_digest"])

    entries =
      Enum.map(members, fn member ->
        %{
          "program" => member.program.data,
          "event" => member.event,
          "snapshot" => %{member.snapshot | "active_programs" => programs},
          "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
        }
      end)

    {%{
       "membership" => %{"generation" => "membership:1", "programs" => programs},
       "entries" => entries,
       "time" => time
     }, programs}
  end

  defp resume_collection(collection) do
    runs = Map.new(collection["transitions"], &{&1["program_digest"], &1["result"]["run"]})

    Map.update!(collection["input"], "entries", fn entries ->
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

  defp results(collection),
    do: Map.new(collection["transitions"], &{&1["result"]["run"]["original"], &1["result"]})
end
