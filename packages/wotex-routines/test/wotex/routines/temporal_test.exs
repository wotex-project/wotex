defmodule Wotex.Routines.TemporalTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Compiler, Error, Kernel, Limits, Profile, Schedule, Temporal}

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

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => 1000,
      "clock_generation" => "clock:1",
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    %{corpus: corpus, limits: limits, profile: profile, time: time}
  end

  test "malformed calendar rules and native schedule values cannot become an empty successful page",
       c do
    raw = %{
      "format" => "wotex.routines.schedule@1",
      "kind" => "calendar",
      "schedule_id" => "schedule:one",
      "definition_digest" => "sha256:" <> String.duplicate("0", 64),
      "late_window_ms" => 1000,
      "rule" => String.duplicate("x", 4097),
      "dtstart" => "2026-10-13T07:00:00Z",
      "time_zone" => "Etc/UTC",
      "time_zone_basis" => "sha256:" <> String.duplicate("6", 64),
      "producer_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    assert {:error, %Error{code: :rule_bound}} = Schedule.new(raw, c.limits)

    unsupported =
      raw
      |> Map.take(~w(format kind schedule_id definition_digest late_window_ms))
      |> Map.put("kind", "unregistered")

    assert {:error, %Error{code: :unsupported_schedule}} = Schedule.new(unsupported, c.limits)
    assert {:error, %Error{code: :invalid_type}} = Schedule.semantic_digest(nil, c.limits)
    assert {:error, %Error{}} = Schedule.semantic_digest(struct!(Schedule, data: nil), c.limits)
    assert {:error, %Error{}} = Schedule.new(%{raw | "dtstart" => "not-a-time"}, c.limits)
  end

  test "cadence pages preserve global ordinals, horizon boundaries and unclipped originals", c do
    schedule = schedule(c, "interval", %{"first_due_ms" => 1000, "period_ms" => 1000})
    query = %{"from_ms" => 2500, "until_ms" => 5000, "limit" => 1}
    assert {:ok, first} = Temporal.page(schedule, query, c.time, nil, c.limits)
    assert [one] = first["occurrences"]
    assert one["due_ms"] == 3000
    assert one["ordinal"] == 3

    assert {:ok, second} =
             Temporal.page(
               schedule,
               %{query | "limit" => 2},
               c.time,
               first["next_cursor"],
               c.limits
             )

    assert [two] = second["occurrences"]
    assert two["due_ms"] == 4000
    assert two["ordinal"] == 4
    assert second["next_cursor"] == nil
    assert one["original"] != two["original"]
    assert {:ok, full} = Temporal.page(schedule, %{query | "limit" => 10}, c.time, nil, c.limits)
    assert full["occurrences"] == [one, two]

    schema =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("schemas/wro-03-temporal.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    for value <- [schedule.data, query, first, first["next_cursor"], one] do
      assert ExJsonSchema.Validator.validate(schema, value) == :ok
    end
  end

  test "independent finite tick oracle covers signed horizons and exact empty boundaries", c do
    for start <- [-20, 0, 20], period <- [1, 3, 7], from <- [-25, -10, 0, 25] do
      schedule = schedule(c, "interval", %{"first_due_ms" => start, "period_ms" => period})
      query = %{"from_ms" => from, "until_ms" => from + 10, "limit" => 100}

      expected =
        for n <- 0..60, due = start + n * period, due >= from and due < from + 10, do: {due, n + 1}

      assert {:ok, page} = Temporal.page(schedule, query, c.time, nil, c.limits)
      assert Enum.map(page["occurrences"], &{&1["due_ms"], &1["ordinal"]}) == expected
    end
  end

  test "a far-future page computes directly without traversing earlier ticks", c do
    schedule = schedule(c, "interval", %{"first_due_ms" => 0, "period_ms" => 7})
    query = %{"from_ms" => 1_000_000_000_000_000, "until_ms" => 1_000_000_000_000_020, "limit" => 2}
    assert {:ok, page} = Temporal.page(schedule, query, c.time, nil, c.limits)

    assert Enum.map(page["occurrences"], & &1["due_ms"]) == [
             1_000_000_000_000_001,
             1_000_000_000_000_008
           ]

    assert hd(page["occurrences"])["ordinal"] == 142_857_142_857_144
  end

  test "clock corrections preserve original identities but invalidate old projections and cursors",
       c do
    schedule = schedule(c, "interval", %{"first_due_ms" => 1000, "period_ms" => 1000})
    query = %{"from_ms" => 1000, "until_ms" => 4000, "limit" => 1}
    {:ok, first} = Temporal.page(schedule, query, c.time, nil, c.limits)
    corrected = %{c.time | "clock_generation" => "clock:2"}
    {:ok, fresh} = Temporal.page(schedule, query, corrected, nil, c.limits)
    assert hd(first["occurrences"])["original"] == hd(fresh["occurrences"])["original"]
    assert hd(first["occurrences"])["event"]["clock_generation"] == "clock:1"

    assert {:error, %Error{code: :stale_temporal_cursor}} =
             Temporal.page(schedule, query, corrected, first["next_cursor"], c.limits)

    program = program(c, schedule)

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Temporal.event(
               schedule,
               hd(first["occurrences"]),
               program,
               corrected,
               c.profile,
               c.limits
             )
  end

  test "countdown runs under boot-local elapsed bounds without UTC confidence", c do
    schedule =
      schedule(c, "countdown", %{
        "due_elapsed_ms" => 1000,
        "epoch" => "boot:1",
        "clock_generation" => "clock:1"
      })

    query = %{"from_ms" => 0, "until_ms" => 2000, "limit" => 1}
    assert {:ok, page} = Temporal.page(schedule, query, c.time, nil, c.limits)
    program = program(c, schedule)

    assert {:ok, event} =
             Temporal.event(schedule, hd(page["occurrences"]), program, c.time, c.profile, c.limits)

    assert event.data["kind"] == "elapsed_due"
    assert {:ok, result} = kernel(c, program, event, c.time)
    assert result["outcome"] == "completed"

    for elapsed <- [999, 1100] do
      assert {:ok, refused} = kernel(c, program, event, %{c.time | "elapsed_ms" => elapsed})
      assert refused["outcome"] == "expired"
      assert refused["proposals"] == []
    end

    for time <- [%{c.time | "epoch" => "boot:2"}, %{c.time | "clock_generation" => "clock:2"}] do
      assert {:error, %Error{code: :changed_time_basis}} =
               Temporal.page(schedule, query, time, nil, c.limits)
    end
  end

  test "one-shots are single originals and mutable schedule fields break program correspondence",
       c do
    schedule = schedule(c, "one_shot", %{"due_ms" => 1000})
    query = %{"from_ms" => 1001, "until_ms" => 2000, "limit" => 1}

    assert {:ok, %{"occurrences" => [], "next_cursor" => nil}} =
             Temporal.page(schedule, query, c.time, nil, c.limits)

    {:ok, page} = Temporal.page(schedule, %{query | "from_ms" => 1000}, c.time, nil, c.limits)
    program = program(c, schedule)
    changed = schedule(c, "one_shot", %{"due_ms" => 1000, "late_window_ms" => 101})

    {:ok, changed_page} =
      Temporal.page(changed, %{query | "from_ms" => 1000}, c.time, nil, c.limits)

    assert {:error, %Error{code: :schedule_program_mismatch}} =
             Temporal.event(
               changed,
               hd(changed_page["occurrences"]),
               program,
               c.time,
               c.profile,
               c.limits
             )

    assert {:error, %Error{code: :schedule_digest_mismatch}} =
             Schedule.new(%{schedule.data | "due_ms" => 1001}, c.limits)

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Temporal.event(
               schedule,
               %{hd(page["occurrences"]) | "due_ms" => 1001},
               program,
               c.time,
               c.profile,
               c.limits
             )
  end

  test "malformed queries, cursor bases and number overflow reject before enumeration", c do
    schedule = schedule(c, "interval", %{"first_due_ms" => 1000, "period_ms" => 1000})
    query = %{"from_ms" => 0, "until_ms" => 4000, "limit" => 1}
    {:ok, page} = Temporal.page(schedule, query, c.time, nil, c.limits)

    for cursor <- [
          %{page["next_cursor"] | "next_ordinal" => 100},
          %{page["next_cursor"] | "query_digest" => "wrong"},
          Map.put(page["next_cursor"], "extra", true)
        ] do
      assert {:error, %Error{}} = Temporal.page(schedule, query, c.time, cursor, c.limits)
    end

    for query <- [%{query | "limit" => 0}, %{query | "until_ms" => 0}, Map.put(query, "now", 1000)] do
      assert {:error, %Error{}} = Temporal.page(schedule, query, c.time, nil, c.limits)
    end

    overflow =
      schedule(c, "interval", %{
        "first_due_ms" => c.limits.data["max_integer"] - 1,
        "period_ms" => 1
      })

    assert {:error, %Error{code: :integer_overflow}} =
             Temporal.page(
               overflow,
               %{
                 "from_ms" => c.limits.data["max_integer"] - 1,
                 "until_ms" => c.limits.data["max_integer"],
                 "limit" => 1
               },
               c.time,
               nil,
               c.limits
             )

    assert {:error, %Error{}} = Schedule.new(struct!(Schedule, data: nil), c.limits)
  end

  defp schedule(c, kind, fields) do
    raw =
      Map.merge(
        %{
          "format" => "wotex.routines.schedule@1",
          "kind" => kind,
          "schedule_id" => "schedule:1",
          "definition_digest" => "sha256:" <> String.duplicate("0", 64),
          "late_window_ms" => 100,
          "time_basis" => "sha256:" <> String.duplicate("6", 64)
        },
        fields
      )

    {:ok, digest} = Schedule.semantic_digest(raw, c.limits)
    {:ok, schedule} = Schedule.new(%{raw | "definition_digest" => digest}, c.limits)
    schedule
  end

  defp program(c, schedule) do
    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "timed",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => [],
      "trigger" => %{
        "kind" => if(schedule.data["kind"] == "countdown", do: "countdown", else: "due"),
        "schedule_id" => schedule.data["schedule_id"],
        "schedule_basis" => schedule.data["definition_digest"]
      },
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => %{"id" => "done", "kind" => "noop"},
      "overlap" => "reject",
      "run_ms" => 1000
    }

    context = %{
      "registry" => c.corpus["registry"],
      "bases" => c.corpus["bases"],
      "bindings" => %{},
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, program} = Compiler.compile(source, context, c.profile, c.limits)
    program
  end

  defp kernel(c, program, event, time) do
    snapshot = %{
      "id" => "snapshot:1",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{},
      "binding_bases" => %{},
      "facts" => %{}
    }

    Kernel.advance(
      program,
      event,
      snapshot,
      time,
      %{"original" => nil, "busy" => nil, "edge" => nil},
      c.profile,
      c.limits
    )
  end
end
