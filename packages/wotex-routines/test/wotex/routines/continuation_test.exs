defmodule Wotex.Routines.ContinuationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Collection, Error, Event, Limits, Profile}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F

  Code.require_file("../../support/continuation_fixtures.exs", __DIR__)

  test "explicit ceilings revalidate native maps without changing old selections" do
    c = F.fixture()
    selected = c.limits.data
    assert {:ok, ^selected} = Limits.to_map(c.limits)
    assert {:ok, old} = Limits.new(c.corpus["limits"])
    assert old.data == c.corpus["limits"]

    for {key, ceiling} <- selected, bad <- [0, ceiling + 1, 1.5] do
      assert {:error, %Error{code: :invalid_limits}} = Limits.new(%{selected | key => bad})

      assert {:error, %Error{code: :invalid_limits}} =
               Limits.to_map(%Limits{data: %{selected | key => bad}})
    end

    assert {:error, %Error{}} = Limits.new(Map.put(c.limits, :extra, 1))
    assert {:error, %Error{}} = Limits.new(Map.delete(selected, "max_nodes"))
  end

  @tag timeout: 60_000
  test "16, 32 and 64 complete members fit the explicit aggregate envelope without truncation" do
    c = F.fixture()

    for count <- c.vectors["traces"]["limits"]["member_counts"] do
      input = F.collection(c, count)
      assert {:ok, collection} = Collection.evaluate(input, c.profile, c.limits)
      assert length(collection.data["transitions"]) == count
      assert length(collection.data["proposals"]) == count
      assert byte_size(JSON.encode!(collection.data)) <= c.limits.data["max_bytes"]

      assert MapSet.new(Enum.map(collection.data["transitions"], & &1["program_digest"])) ==
               MapSet.new(input["membership"]["programs"])
    end

    old = F.fixture(limits: %{c.limits.data | "max_bytes" => 1_048_576})
    input = F.collection(old, 64)
    assert byte_size(JSON.encode!(input)) < old.limits.data["max_bytes"]

    assert {:error, %Error{code: :limit_or_json_error}} =
             Collection.evaluate(input, old.profile, old.limits)

    {:ok, narrow} = Profile.new(%{c.profile.data | "pending_work" => 15})
    input = F.collection(%{c | profile: narrow}, 16)

    assert {:error, %Error{code: :pending_work_bound}} =
             Collection.evaluate(input, narrow, c.limits)
  end

  test "resume is closed and cannot create an original or substitute a busy index" do
    c =
      F.fixture()
      |> F.compile()
      |> F.resume()

    assert {:ok, event} = Event.new(c.event, c.limits)
    assert Event.to_map(event, c.limits) == {:ok, c.event}
    assert {:error, %Error{code: :missing_original}} = F.advance(c)
    assert {:error, %Error{}} = Event.new(Map.put(c.event, "fact_id", "sample:1"), c.limits)
    assert {:error, %Error{}} = Event.new(Map.put(event, :extra, true), c.limits)

    {:ok, first} = F.advance(%{c | event: %{c.event | "kind" => "manual"}})
    assert {:error, %Error{code: :missing_original}} = F.advance(c, nil, nil, first["run"])
    removed = %{c | snapshot: %{c.snapshot | "active_programs" => []}}
    assert {:error, %Error{code: :missing_original}} = F.advance(removed)

    assert {:error, %Error{code: :foreign_original}} =
             F.advance(%{c | event: %{c.event | "original" => "other"}}, first["run"])
  end

  test "neutral manual continuation follows the independent elapsed boundary trace" do
    c = F.fixture() |> F.compile(%{"steps" => F.delayed_effect()})
    {:ok, first} = F.advance(c)
    assert first["proposals"] == []
    resume = F.resume(c)

    final =
      Enum.reduce(c.vectors["traces"]["manual_delay"]["samples"], first, fn sample, prior ->
        {:ok, result} =
          F.advance(
            %{resume | time: %{c.time | "elapsed_ms" => sample["elapsed_ms"]}},
            prior["run"]
          )

        assert Enum.map(result["proposals"], & &1["path"]) == sample["proposed_paths"]
        assert result["run"]["original"] == first["run"]["original"]
        result
      end)

    {:ok, repeated} = F.advance(%{resume | time: %{c.time | "elapsed_ms" => 120}}, final["run"])
    assert repeated["proposals"] == []
    assert repeated["run"] == final["run"]
  end

  test "an edge-origin delay resumes with a changed snapshot without consuming an edge sample" do
    trigger = %{
      "kind" => "edge",
      "binding" => "sensor",
      "direction" => "rising",
      "debounce_ms" => 0,
      "cooldown_ms" => 200,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    c = F.fixture(sensor: true) |> F.compile(%{"trigger" => trigger, "steps" => F.delayed_effect()})
    baseline = F.sample(c, 1, 20, 1000)
    {:ok, first} = F.advance(baseline)
    assert first["outcome"] == "no-edge"
    active = F.sample(c, 2, 30, 3000)
    {:ok, started} = F.advance(active, nil, first["edge"])
    assert started["outcome"] == "running"
    assert started["proposals"] == []
    changed = F.sample(c, 3, 130, 1000)
    resume = %{F.resume(active) | snapshot: changed.snapshot, time: changed.time}
    {:ok, ready} = F.advance(resume, started["run"], started["edge"])
    assert Enum.map(ready["proposals"], & &1["path"]) == [[1]]
    assert ready["run"]["original"] == "original:2"
    assert ready["edge"] == started["edge"]
  end

  test "resume reevaluates an unknown wait against the current qualified Fact" do
    steps = %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [
        %{
          "id" => "await",
          "kind" => "wait",
          "condition" => %{"op" => "gt", "binding" => "sensor", "value" => 2000},
          "timeout_ms" => 500
        },
        F.effect("after")
      ]
    }

    c = F.fixture(sensor: true) |> F.compile(%{"steps" => steps})
    {:ok, waiting} = F.advance(c)
    assert waiting["proposals"] == []
    sample = F.sample(c, 8, 119, 3000)
    resume = %{F.resume(c) | snapshot: sample.snapshot, time: sample.time}
    {:ok, ready} = F.advance(resume, waiting["run"])
    assert Enum.map(ready["proposals"], & &1["path"]) == [[1]]
    assert ready["run"]["original"] == waiting["run"]["original"]
    assert ready["edge"] == nil
  end

  test "UTC and countdown continuation retain the original immutable window" do
    basis = "sha256:" <> String.duplicate("6", 64)

    for kind <- ["due", "countdown"] do
      trigger = %{"kind" => kind, "schedule_id" => "schedule:1", "schedule_basis" => basis}
      c = F.fixture() |> F.compile(%{"trigger" => trigger, "steps" => F.delayed_effect()})

      common =
        Map.merge(c.event, %{
          "schedule_id" => "schedule:1",
          "schedule_basis" => basis,
          "clock_generation" => c.time["clock_generation"],
          "late_window_ms" => 500
        })

      event =
        if kind == "due",
          do: Map.merge(common, %{"kind" => "due", "due_ms" => 1000, "time_zone_basis" => basis}),
          else:
            Map.merge(common, %{
              "kind" => "elapsed_due",
              "due_elapsed_ms" => 20,
              "epoch" => c.time["epoch"],
              "time_basis" => basis
            })

      c = %{c | event: event, time: %{c.time | "utc_low_ms" => 1000, "utc_high_ms" => 1000}}
      {:ok, first} = F.advance(c)

      resume = %{
        F.resume(c)
        | time: %{c.time | "elapsed_ms" => 120, "utc_low_ms" => 1100, "utc_high_ms" => 1100}
      }

      {:ok, ready} = F.advance(resume, first["run"])
      assert Enum.map(ready["proposals"], & &1["path"]) == [[1]]
      assert ready["run"]["window"] == first["run"]["window"]
      assert Map.keys(ready["basis"]["event"]) |> Enum.sort() == ~w(kind original program_digest)
    end
  end

  test "resume expires or cancels unsent work while preserving handed-off history and spend" do
    c =
      F.fixture()
      |> F.compile(%{
        "steps" => %{
          "id" => "parallel",
          "kind" => "parallel",
          "branches" => [F.effect("first"), F.delayed_effect()]
        }
      })

    {:ok, first} = F.advance(c)

    admission =
      Map.merge(c.event, %{
        "kind" => "admission",
        "path" => [0],
        "ref" => "charge:1",
        "outcome" => "held"
      })

    {:ok, held} = F.advance(%{c | event: admission}, first["run"])
    handoff = Map.merge(c.event, %{"kind" => "handoff", "path" => [0], "ref" => "handoff:1"})
    {:ok, handed} = F.advance(%{c | event: handoff}, held["run"])
    resume = F.resume(c)

    for {field, value, reason} <- [
          {"epoch", "boot:2", "clock_changed"},
          {"clock_generation", "elapsed:2", "clock_changed"},
          {"elapsed_ms", 19, "clock_regressed"},
          {"elapsed_ms", 1020, "deadline_elapsed"}
        ] do
      {:ok, expired} = F.advance(%{resume | time: Map.put(c.time, field, value)}, handed["run"])
      assert expired["outcome"] == "expired"
      assert expired["run"]["reason"] == reason
      assert expired["proposals"] == []
      assert expired["run"]["spent"] == handed["run"]["spent"]
      before = Enum.find(handed["run"]["steps"], &(&1["path"] == [0]))
      after_expiry = Enum.find(expired["run"]["steps"], &(&1["path"] == [0]))
      assert after_expiry["status"] == "unknown"
      assert after_expiry["receipts"] == before["receipts"]
      {:ok, replay} = F.advance(resume, expired["run"])
      assert replay["run"] == expired["run"]
    end

    removed = %{resume | snapshot: %{resume.snapshot | "active_programs" => []}}
    {:ok, cancelled} = F.advance(removed, handed["run"])
    assert cancelled["outcome"] == "cancelled"
    assert cancelled["run"]["spent"] == handed["run"]["spent"]
  end

  test "terminal resume is exact after full native input validation" do
    c = F.fixture() |> F.compile(%{"steps" => %{"id" => "done", "kind" => "noop"}})
    {:ok, completed} = F.advance(c)
    assert completed["outcome"] == "completed"
    resume = F.resume(c)

    {:ok, replay} =
      F.advance(
        %{resume | time: %{c.time | "epoch" => "boot:2", "elapsed_ms" => 5000}},
        completed["run"]
      )

    assert replay["run"] == completed["run"]
    assert replay["proposals"] == []

    assert {:error, %Error{}} =
             F.advance(%{resume | time: Map.put(c.time, "untrusted", true)}, completed["run"])
  end
end
