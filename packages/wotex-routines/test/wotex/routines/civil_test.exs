Code.require_file("../../support/civil_fixtures.exs", __DIR__)

defmodule Wotex.Routines.CivilTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Civil, CivilPage, CivilRequest, Error, Limits, Schedule}
  alias Wotex.Routines.Test.CivilFixtures, as: F

  setup_all do
    F.load()
  end

  test "the explicit civil schedule accepts the frozen contract vector", c do
    assert {:ok, schedule} = Schedule.new(c.schedule, c.limits)
    assert schedule.data == c.schedule
    assert :ok == ExJsonSchema.Validator.validate(c.schema, c.schedule)
    assert :ok == ExJsonSchema.Validator.validate(c.schema, c.query)

    assert {:ok, request} =
             CivilRequest.new(schedule, c.query, Calendar.UTCOnlyTimeZoneDatabase, c.limits)

    assert CivilRequest.current(request, c.limits) == {:ok, request}
  end

  test "the selected released producer has no civil API and no recurrence fallback", c do
    {:ok, request} =
      CivilRequest.new(c.schedule, c.query, Calendar.UTCOnlyTimeZoneDatabase, c.limits)

    assert {:error, %Error{code: :civil_unavailable}} = Civil.page(request, c.time, c.limits)
    assert {:error, %Error{code: :invalid_civil_page}} = Civil.to_map(%{}, c.limits)

    assert {:error, %Error{}} =
             Civil.to_map(struct!(CivilPage, request: nil, time: nil, occurrences: nil), c.limits)

    assert {:error, %Error{}} = Civil.page(request, c.time, %{})
    assert {:error, %Error{}} = Civil.page(request, %{}, c.limits)
  end

  test "closed patterns refuse missing fields, implicit defaults and invalid labels", c do
    for key <- Map.keys(c.schedule) do
      assert {:error, %Error{}} = Schedule.new(Map.delete(c.schedule, key), c.limits)
    end

    for change <- [
          %{"time" => "09:00"},
          %{"time" => "09:00:00.000"},
          %{"time" => "24:00:00"},
          %{"time" => 90_000},
          %{"weekdays" => []},
          %{"weekdays" => [1, 1]},
          %{"weekdays" => [3, 1]},
          %{"weekdays" => [0]},
          %{"weekdays" => [1.0]},
          %{"weekdays" => [1, 2, 3, 4, 5, 6, 7, 8]},
          %{"time_zone" => String.duplicate("x", 257)},
          %{"gap_policy" => "snap"},
          %{"fold_policy" => "default"},
          %{"ordinal" => 1},
          %{"dtstart" => "2026-07-13T09:00:00Z"}
        ] do
      assert {:error, %Error{}} = Schedule.new(F.schedule(c, change), c.limits)
    end

    assert {:error, %Error{}} = Schedule.new(%{c.schedule | "late_window_ms" => 0}, c.limits)

    assert {:error, %Error{code: :schedule_digest_mismatch}} =
             Schedule.new(%{c.schedule | "fold_policy" => "both"}, c.limits)

    assert {:error, %Error{}} =
             CivilRequest.new(
               Map.put(c.schedule, "__struct__", Schedule),
               c.query,
               Calendar.UTCOnlyTimeZoneDatabase,
               c.limits
             )
  end

  test "finite local spans, fractional endpoints, explicit database and native shapes are checked",
       c do
    for change <- [
          %{"first_date" => "10000-01-01"},
          %{"first_date" => "2026-02-30"},
          %{"first_date" => "9999-12-31", "days" => 2},
          %{"days" => 0},
          %{"days" => 367},
          %{"days" => true},
          %{"from" => c.query["until"]},
          %{"until" => "broken"},
          %{"from" => "0000-01-01T00:00:00+01:00"},
          %{"until" => "9999-12-31T23:59:59-01:00"},
          %{"limit" => 1}
        ] do
      assert {:error, %Error{}} =
               CivilRequest.new(
                 c.schedule,
                 Map.merge(c.query, change),
                 Calendar.UTCOnlyTimeZoneDatabase,
                 c.limits
               )
    end

    for key <- Map.keys(c.query) do
      assert {:error, %Error{}} =
               CivilRequest.new(
                 c.schedule,
                 Map.delete(c.query, key),
                 Calendar.UTCOnlyTimeZoneDatabase,
                 c.limits
               )
    end

    for db <- [
          nil,
          "Calendar.UTCOnlyTimeZoneDatabase",
          Schedule,
          %{__struct__: ExBooking.TimeZoneProvider, module: Schedule, context: "bad"}
        ] do
      assert {:error, %Error{code: :invalid_civil_request}} =
               CivilRequest.new(c.schedule, c.query, db, c.limits)
    end

    {:ok, request} =
      CivilRequest.new(c.schedule, c.query, Calendar.UTCOnlyTimeZoneDatabase, c.limits)

    assert request.query["from"] == c.query["from"]
    shifted = %{c.query | "from" => "2026-07-13T10:00:00.000001+01:00"}

    assert {:ok, ^request} =
             CivilRequest.new(c.schedule, shifted, Calendar.UTCOnlyTimeZoneDatabase, c.limits)

    assert {:error, %Error{}} = CivilRequest.current(Map.put(request, :extra, nil), c.limits)
    assert {:error, %Error{}} = CivilRequest.current(%{__struct__: CivilRequest}, c.limits)

    forged =
      request
      |> Map.delete(:database)
      |> Map.put(:extra, nil)

    assert {:error, %Error{code: :invalid_civil_request}} = CivilRequest.current(forged, c.limits)

    assert {:error, %Error{code: :invalid_civil_page}} =
             Civil.to_map(
               %{__struct__: CivilPage, request: request, occurrences: [], extra: nil},
               c.limits
             )

    assert {:error, %Error{}} = CivilRequest.current(%{}, c.limits)
    {:ok, tiny} = Limits.new(%{c.limits.data | "max_bytes" => 128})

    assert {:error, %Error{}} =
             CivilRequest.new(c.schedule, c.query, Calendar.UTCOnlyTimeZoneDatabase, tiny)
  end
end
