defmodule Wotex.Routines.CalendarTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.Calendar, as: Adapter
  alias Wotex.Routines.{CalendarCursor, CalendarPage, CalendarRequest, Error, Limits, Schedule}

  setup_all do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, limits} = Limits.new(corpus["limits"])

    schedule = %{
      "format" => "wotex.routines.schedule@1",
      "kind" => "calendar",
      "schedule_id" => "calendar:1",
      "definition_digest" => "sha256:" <> String.duplicate("0", 64),
      "late_window_ms" => 1000,
      "rule" => "FREQ=DAILY;COUNT=3",
      "dtstart" => "2026-10-13T07:00:00Z",
      "time_zone" => "Etc/UTC",
      "time_zone_basis" => "sha256:" <> String.duplicate("6", 64),
      "producer_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, digest} = Schedule.semantic_digest(schedule, limits)
    {:ok, schedule} = Schedule.new(%{schedule | "definition_digest" => digest}, limits)

    query = %{
      "from" => "2026-10-13T08:00:00+01:00",
      "until" => "2026-10-16T00:00:00Z",
      "limit" => 1,
      "work_limit" => 100
    }

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => 1000,
      "clock_generation" => "clock:1",
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    %{limits: limits, schedule: schedule, query: query, time: time}
  end

  test "the exact published producer refuses the missing API without an availability fallback", c do
    assert {:ok, request} =
             CalendarRequest.new(
               c.schedule,
               c.query,
               Calendar.UTCOnlyTimeZoneDatabase,
               nil,
               c.limits
             )

    assert request.query["from"] == "2026-10-13T07:00:00Z"
    assert {:error, %Error{code: :recurrence_unavailable}} = Adapter.page(request, c.time, c.limits)
    assert CalendarRequest.current(request, c.limits) == {:ok, request}
  end

  test "all calendar query bounds and native request/envelope shapes are explicit", c do
    for query <- [
          %{c.query | "from" => c.query["until"]},
          %{c.query | "limit" => 0},
          %{c.query | "limit" => 1025},
          %{c.query | "work_limit" => 100_001},
          %{c.query | "from" => "broken"},
          Map.put(c.query, "now", "ignored")
        ] do
      assert {:error, %Error{}} =
               CalendarRequest.new(
                 c.schedule,
                 query,
                 Calendar.UTCOnlyTimeZoneDatabase,
                 nil,
                 c.limits
               )
    end

    assert {:error, %Error{}} =
             CalendarRequest.new(c.schedule, c.query, "Tz.TimeZoneDatabase", nil, c.limits)

    assert {:error, %Error{}} = CalendarRequest.current(%{__struct__: CalendarRequest}, c.limits)

    for cursor <- [
          %{},
          %CalendarCursor{basis_digest: "bad", clock_generation: "clock:1", producer_cursor: %{}},
          %CalendarCursor{
            basis_digest: "sha256:" <> String.duplicate("8", 64),
            clock_generation: "clock:1",
            producer_cursor: nil
          }
        ] do
      assert {:error, %Error{}} =
               CalendarRequest.new(
                 c.schedule,
                 c.query,
                 Calendar.UTCOnlyTimeZoneDatabase,
                 cursor,
                 c.limits
               )
    end

    assert {:error, %Error{code: :invalid_calendar_page}} = Adapter.to_map(%{}, c.limits)

    assert {:error, %Error{}} =
             Adapter.to_map(
               struct!(CalendarPage, request: nil, time: nil, occurrences: nil, next_cursor: nil),
               c.limits
             )
  end

  test "changed cursor and mismatched DTSTART offset refuse before producer dispatch", c do
    cursor = %CalendarCursor{
      basis_digest: "sha256:" <> String.duplicate("8", 64),
      clock_generation: "clock:old",
      producer_cursor: %{}
    }

    {:ok, request} =
      CalendarRequest.new(c.schedule, c.query, Calendar.UTCOnlyTimeZoneDatabase, cursor, c.limits)

    assert {:error, %Error{code: :stale_calendar_cursor}} = Adapter.page(request, c.time, c.limits)
    raw = %{c.schedule.data | "dtstart" => "2026-10-13T07:00:00+01:00"}
    {:ok, digest} = Schedule.semantic_digest(raw, c.limits)
    {:ok, schedule} = Schedule.new(%{raw | "definition_digest" => digest}, c.limits)

    {:ok, request} =
      CalendarRequest.new(schedule, c.query, Calendar.UTCOnlyTimeZoneDatabase, nil, c.limits)

    assert {:error, %Error{code: :invalid_calendar_start}} = Adapter.page(request, c.time, c.limits)
  end
end
