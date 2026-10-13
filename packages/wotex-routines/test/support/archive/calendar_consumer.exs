defmodule CalendarArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.Calendar, as: Adapter
  alias Wotex.Routines.{CalendarCursor, CalendarRequest, Compiler, Error, Limits, Profile, Schedule}

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

  test "archive code and the original-occurrence capability come from this isolated build", _ do
    root = File.cwd!()
    supplied = System.fetch_env!("WOTEX_ROUTINES_CONSUMER_ROOT")

    assert Map.take(File.stat!(root), [:inode, :major_device]) ==
             Map.take(File.stat!(supplied), [:inode, :major_device])

    for module <- [
          ExBooking,
          Wotex.Routines.Compiler,
          Wotex.Routines.Calendar,
          Wotex.JSON,
          WotexContinuum
        ] do
      Code.ensure_loaded!(module)

      assert module
             |> :code.which()
             |> List.to_string()
             |> String.starts_with?(Path.join(root, "_build"))
    end

    assert function_exported?(ExBooking, :occurrences, 3)

    assert Application.spec(:wotex_routines, :mod) in [nil, []]
  end

  test "global COUNT, original nominal instants and paging survive a later horizon", c do
    request =
      request(
        c,
        "2026-10-13T07:00:00Z",
        "Etc/UTC",
        "2026-10-14T00:00:00Z",
        "2026-10-17T00:00:00Z",
        "FREQ=DAILY;COUNT=3",
        1
      )

    assert {:ok, first} = Adapter.page(request, c.time, c.limits)
    assert [{"2026-10-14T07:00:00", "2026-10-14T07:00:00Z", 2, "unique"}] == coordinates(first)
    assert %CalendarCursor{} = first.next_cursor
    next = %{request | cursor: first.next_cursor, query: %{request.query | "limit" => 2}}
    assert {:ok, second} = Adapter.page(next, c.time, c.limits)
    assert [{"2026-10-15T07:00:00", "2026-10-15T07:00:00Z", 3, "unique"}] == coordinates(second)
    assert second.next_cursor == nil
    assert {:ok, wire} = Adapter.to_map(first, c.limits)
    assert wire["has_more"] == true

    schema =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("schemas/wro-03-temporal.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, wire) == :ok
    assert ExJsonSchema.Validator.validate(schema, hd(first.occurrences)) == :ok
  end

  test "duration-free enumeration never clips an old due instant into the query", c do
    request =
      request(
        c,
        "2026-10-13T07:00:00Z",
        "Etc/UTC",
        "2026-10-13T07:00:01Z",
        "2026-10-14T00:00:00Z",
        "FREQ=DAILY;COUNT=1"
      )

    assert {:ok, page} = Adapter.page(request, c.time, c.limits)
    assert page.occurrences == []
    assert page.next_cursor == nil
  end

  test "Stockholm gap skips without consuming COUNT and folds retain the first recurrence instant",
       c do
    gap =
      request(
        c,
        "2026-03-28T02:30:00+01:00",
        "Europe/Stockholm",
        "2026-03-28T00:00:00Z",
        "2026-04-01T00:00:00Z",
        "FREQ=DAILY;COUNT=3"
      )

    assert {:ok, page} = Adapter.page(gap, c.time, c.limits)

    assert Enum.map(page.occurrences, & &1["starts_at"]) == [
             "2026-03-28T01:30:00Z",
             "2026-03-30T00:30:00Z",
             "2026-03-31T00:30:00Z"
           ]

    assert Enum.map(page.occurrences, & &1["ordinal"]) == [1, 2, 3]

    fold =
      request(
        c,
        "2026-10-24T02:30:00+02:00",
        "Europe/Stockholm",
        "2026-10-24T00:00:00Z",
        "2026-10-27T00:00:00Z",
        "FREQ=DAILY;COUNT=3"
      )

    assert {:ok, page} = Adapter.page(fold, c.time, c.limits)

    assert Enum.map(page.occurrences, &{&1["starts_at"], &1["resolution"]}) == [
             {"2026-10-24T00:30:00Z", "unique"},
             {"2026-10-25T00:30:00Z", "first_fold"},
             {"2026-10-26T01:30:00Z", "unique"}
           ]
  end

  test "the supplied second-fold DTSTART remains its own original", c do
    request =
      request(
        c,
        "2026-10-25T02:30:00+01:00",
        "Europe/Stockholm",
        "2026-10-25T00:00:00Z",
        "2026-10-27T00:00:00Z",
        "FREQ=DAILY;COUNT=2"
      )

    assert {:ok, page} = Adapter.page(request, c.time, c.limits)

    assert Enum.map(page.occurrences, &{&1["starts_at"], &1["resolution"]}) == [
             {"2026-10-25T01:30:00Z", "second_fold"},
             {"2026-10-26T01:30:00Z", "unique"}
           ]
  end

  test "New York gap and fold vectors retain their independent UTC coordinates", c do
    gap =
      request(
        c,
        "2026-03-07T02:30:00-05:00",
        "America/New_York",
        "2026-03-07T00:00:00Z",
        "2026-03-11T00:00:00Z",
        "FREQ=DAILY;COUNT=3"
      )

    assert {:ok, page} = Adapter.page(gap, c.time, c.limits)

    assert Enum.map(page.occurrences, & &1["starts_at"]) == [
             "2026-03-07T07:30:00Z",
             "2026-03-09T06:30:00Z",
             "2026-03-10T06:30:00Z"
           ]

    fold =
      request(
        c,
        "2026-10-31T01:30:00-04:00",
        "America/New_York",
        "2026-10-31T00:00:00Z",
        "2026-11-03T00:00:00Z",
        "FREQ=DAILY;COUNT=3"
      )

    assert {:ok, page} = Adapter.page(fold, c.time, c.limits)

    assert Enum.map(page.occurrences, &{&1["starts_at"], &1["resolution"]}) == [
             {"2026-10-31T05:30:00Z", "unique"},
             {"2026-11-01T05:30:00Z", "first_fold"},
             {"2026-11-02T06:30:00Z", "unique"}
           ]
  end

  test "altered retained pages, stale cursor projections and forged members cannot bind a program",
       c do
    request =
      request(
        c,
        "2026-10-13T07:00:00Z",
        "Etc/UTC",
        "2026-10-13T00:00:00Z",
        "2026-10-17T00:00:00Z",
        "FREQ=DAILY",
        1
      )

    assert {:ok, page} = Adapter.page(request, c.time, c.limits)
    program = program(c, request.schedule)
    occurrence = hd(page.occurrences)
    assert {:ok, event} = Adapter.event(page, occurrence, program, c.time, c.profile, c.limits)
    assert event.data["original"] == occurrence["original"]
    assert event.data["schedule_basis"] == request.schedule["definition_digest"]

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Adapter.event(
               page,
               %{occurrence | "due_ms" => occurrence["due_ms"] + 1},
               program,
               c.time,
               c.profile,
               c.limits
             )

    altered = %{page | occurrences: [%{occurrence | "due_ms" => occurrence["due_ms"] + 1}]}
    assert {:error, %Error{code: :stale_calendar_page}} = Adapter.to_map(altered, c.limits)
    corrected = %{c.time | "clock_generation" => "clock:2"}

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Adapter.event(page, occurrence, program, corrected, c.profile, c.limits)

    assert {:error, %Error{code: :stale_calendar_cursor}} =
             Adapter.page(%{request | cursor: page.next_cursor}, corrected, c.limits)

    assert {:ok, fresh} = Adapter.page(request, corrected, c.limits)
    assert hd(fresh.occurrences)["original"] == occurrence["original"]
  end

  test "producer grammar/work refusals and submillisecond starts stay explicit", c do
    request =
      request(
        c,
        "2026-10-13T07:00:00Z",
        "Etc/UTC",
        "2026-10-15T00:00:00Z",
        "2026-10-17T00:00:00Z",
        "FREQ=DAILY"
      )

    assert {:error, %Error{code: :recurrence_work_bound}} =
             Adapter.page(
               %{request | query: %{request.query | "work_limit" => 1}},
               c.time,
               c.limits
             )

    unsupported =
      request(
        c,
        "2026-10-13T07:00:00Z",
        "Etc/UTC",
        "2026-10-13T00:00:00Z",
        "2026-10-17T00:00:00Z",
        "FREQ=MONTHLY"
      )

    assert {:error, %Error{code: :recurrence_refused}} = Adapter.page(unsupported, c.time, c.limits)

    precise =
      request(
        c,
        "2026-10-13T07:00:00.123456Z",
        "Etc/UTC",
        "2026-10-13T00:00:00Z",
        "2026-10-17T00:00:00Z",
        "FREQ=DAILY;COUNT=1"
      )

    assert {:error, %Error{code: :unsupported_temporal_precision}} =
             Adapter.page(precise, c.time, c.limits)
  end

  defp request(c, dtstart, zone, from, until, rule, limit \\ 10) do
    raw = %{
      "format" => "wotex.routines.schedule@1",
      "kind" => "calendar",
      "schedule_id" => "calendar:1",
      "definition_digest" => "sha256:" <> String.duplicate("0", 64),
      "late_window_ms" => 1000,
      "rule" => rule,
      "dtstart" => dtstart,
      "time_zone" => zone,
      "time_zone_basis" => "sha256:" <> String.duplicate("6", 64),
      "producer_basis" => System.fetch_env!("WOTEX_ROUTINES_PRODUCER_BASIS")
    }

    {:ok, digest} = Schedule.semantic_digest(raw, c.limits)
    {:ok, schedule} = Schedule.new(%{raw | "definition_digest" => digest}, c.limits)

    {:ok, request} =
      CalendarRequest.new(
        schedule,
        %{"from" => from, "until" => until, "limit" => limit, "work_limit" => 1000},
        Tz.TimeZoneDatabase,
        nil,
        c.limits
      )

    request
  end

  defp coordinates(page),
    do:
      Enum.map(page.occurrences, &{&1["nominal"], &1["starts_at"], &1["ordinal"], &1["resolution"]})

  defp program(c, schedule) do
    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "calendar",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => [],
      "trigger" => %{
        "kind" => "due",
        "schedule_id" => schedule["schedule_id"],
        "schedule_basis" => schedule["definition_digest"]
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
      "compiler_basis" => System.fetch_env!("WOTEX_ROUTINES_COMPILER_BASIS")
    }

    {:ok, program} = Compiler.compile(source, context, c.profile, c.limits)
    program
  end
end
