Code.require_file("../civil_fixtures.exs", __DIR__)

defmodule CivilArchiveProvider do
  @moduledoc false

  @behaviour ExBooking.TimeZoneProvider

  @impl ExBooking.TimeZoneProvider
  def resolve(nominal, zone, context) do
    count(context, :resolve)

    case context do
      "iana" ->
        case DateTime.from_naive(nominal, zone, Tz.TimeZoneDatabase) do
          {:gap, _, _} -> :gap
          value -> value
        end

      "folds" ->
        value = %{DateTime.from_naive!(nominal, "Etc/UTC") | time_zone: zone}
        {:ambiguous, %{value | utc_offset: 3600}, value}

      "refuse" ->
        {:error, :PRIVATE_CIVIL_CANARY}

      "late" when nominal.day == 14 ->
        {:error, :PRIVATE_CIVIL_CANARY}

      _ ->
        {:ok,
         %{DateTime.from_naive!(nominal, "Etc/UTC") | time_zone: zone, utc_offset: offset(context)}}
    end
  end

  @impl ExBooking.TimeZoneProvider
  def localize(instant, zone, context) do
    count(context, :localize)

    case context do
      "iana" ->
        DateTime.shift_zone(instant, zone, Tz.TimeZoneDatabase)

      _ ->
        offset = if context == "folds" and instant.hour == 8, do: 3600, else: offset(context)

        local =
          instant
          |> DateTime.to_naive()
          |> NaiveDateTime.add(offset)

        {:ok, %{DateTime.from_naive!(local, "Etc/UTC") | time_zone: zone, utc_offset: offset}}
    end
  end

  defp offset("late"), do: 0
  defp offset(<<value::signed-32>>), do: value
  defp offset(_), do: 0

  defp count(context, kind) do
    key = {__MODULE__, context, kind}
    Process.put(key, Process.get(key, 0) + 1)
  end
end

defmodule CompleteCivilArchiveProvider do
  @moduledoc false

  @behaviour ExBooking.TimeZoneProvider

  @impl ExBooking.TimeZoneProvider
  def resolve(_, _, context) do
    count(context, :legacy)
    {:error, :legacy_unsupported}
  end

  @impl ExBooking.TimeZoneProvider
  def resolve_civil(nominal, zone, <<size::16>> = context) do
    count(context, :resolve)
    wall = DateTime.from_naive!(nominal, "Etc/UTC")
    {:ambiguous, for(index <- 1..size, do: %{wall | time_zone: zone, utc_offset: size - index})}
  end

  @impl ExBooking.TimeZoneProvider
  def localize(instant, zone, context) do
    count(context, :localize)
    offset = 9 * 3600 - (instant.hour * 3600 + instant.minute * 60 + instant.second)
    {:ok, %{DateTime.add(instant, offset) | time_zone: zone, utc_offset: offset}}
  end

  defp count(context, kind) do
    key = {__MODULE__, context, kind}
    Process.put(key, Process.get(key, 0) + 1)
  end
end

defmodule CivilArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{Civil, CivilRequest, Error, Limits}
  alias Wotex.Routines.Test.CivilFixtures, as: F

  setup_all do
    c = F.load()

    %{
      c
      | schedule:
          F.schedule(c, %{"producer_basis" => System.fetch_env!("WOTEX_ROUTINES_PRODUCER_BASIS")})
    }
  end

  test "the isolated public archive supplies real civil calculation and closed projection", c do
    for module <- [ExBooking, Wotex.Routines.Civil, Wotex.Routines.CivilRequest] do
      Code.ensure_loaded!(module)

      assert module
             |> :code.which()
             |> List.to_string()
             |> String.starts_with?(Path.join(File.cwd!(), "_build"))
    end

    assert function_exported?(ExBooking, :civil_occurrences, 3)
    request = request(c)
    assert {:ok, page} = Civil.page(request, c.time, c.limits)

    assert coordinates(page) ==
             Enum.map(c.vector["expected"], &Map.take(&1, ~w(nominal starts_at resolution)))

    assert {:ok, wire} = Civil.to_map(page, c.limits)
    assert :ok == ExJsonSchema.Validator.validate(c.schema, wire)
    [point] = page.occurrences
    refute Map.has_key?(point, "ordinal")
    assert :ok == ExJsonSchema.Validator.validate(c.schema, point)
    program = F.program(c, c.schedule)
    assert {:ok, event} = Civil.event(page, point, program, c.time, c.profile, c.limits)
    assert event.data["original"] == point["original"]
  end

  test "literal folds and gaps in both zones keep policies before UTC filtering", c do
    for {zone, date, clock, expected, gap_date, gap_clock} <- [
          {"Europe/Stockholm", "2026-10-25", "02:30:00",
           ["2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z"], "2026-03-29", "02:30:00"},
          {"America/New_York", "2026-11-01", "01:30:00",
           ["2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z"], "2026-03-08", "02:30:00"}
        ],
        db <- [Tz.TimeZoneDatabase, provider("iana")] do
      schedule =
        F.schedule(c, %{
          "time" => clock,
          "weekdays" => [7],
          "time_zone" => zone,
          "fold_policy" => "both"
        })

      query = %{
        "first_date" => date,
        "days" => 1,
        "from" => date <> "T00:00:00Z",
        "until" => date <> "T23:59:59Z"
      }

      request = request(c, query, db, schedule)
      assert {:ok, page} = Civil.page(request, c.time, c.limits)
      assert Enum.map(page.occurrences, & &1["starts_at"]) == expected
      assert Enum.map(page.occurrences, & &1["resolution"]) == ["first_fold", "second_fold"]

      for {policy, values} <- [{"first", [hd(expected)]}, {"second", [List.last(expected)]}] do
        selected = F.schedule(c, Map.merge(schedule, %{"fold_policy" => policy}))
        assert {:ok, page} = Civil.page(%{request | schedule: selected}, c.time, c.limits)
        assert Enum.map(page.occurrences, & &1["starts_at"]) == values
      end

      first = F.schedule(c, Map.merge(schedule, %{"fold_policy" => "first"}))
      filtered = %{request | schedule: first, query: %{query | "from" => List.last(expected)}}
      assert {:ok, %{occurrences: []}} = Civil.page(filtered, c.time, c.limits)
      reject = F.schedule(c, Map.merge(schedule, %{"fold_policy" => "reject"}))

      assert {:error, %Error{code: :civil_refused}} =
               Civil.page(%{filtered | schedule: reject}, c.time, c.limits)

      gap_schedule = F.schedule(c, %{"time" => gap_clock, "weekdays" => [7], "time_zone" => zone})

      gap_query = %{
        "first_date" => gap_date,
        "days" => 1,
        "from" => date <> "T00:00:00Z",
        "until" => date <> "T23:59:59Z"
      }

      gap = request(c, gap_query, db, gap_schedule)
      assert {:ok, %{occurrences: []}} = Civil.page(gap, c.time, c.limits)
      reject = F.schedule(c, Map.merge(gap_schedule, %{"gap_policy" => "reject"}))

      assert {:error, %Error{code: :civil_refused}} =
               Civil.page(%{gap | schedule: reject}, c.time, c.limits)
    end
  end

  test "the civil offset profile uses actual callbacks without the narrower legacy helper", c do
    for offset <- [-89_999, -86_400, 86_400, 93_599] do
      db = provider(<<offset::signed-32>>)
      schedule = F.schedule(c, %{"weekdays" => [1], "time_zone" => "Synthetic/Wide"})

      request =
        request(
          c,
          %{"days" => 1, "from" => "2026-07-11T00:00:00Z", "until" => "2026-07-16T00:00:00Z"},
          db,
          schedule
        )

      assert {:ok, %{occurrences: [point]}} = Civil.page(request, c.time, c.limits)
      expected = DateTime.to_unix(~U[2026-07-13 09:00:00Z], :millisecond) - offset * 1000
      assert point["due_ms"] == expected

      if abs(offset) > 86_400 do
        assert {:error, _} =
                 ExBooking.TimeZoneProvider.from_naive(
                   ~N[2026-07-13 09:00:00],
                   "Synthetic/Wide",
                   db
                 )
      end
    end
  end

  test "independent Gregorian weekday arithmetic agrees over a finite partition corpus", c do
    for start <- [~D[2000-02-26], ~D[2026-07-13]], mask <- [1, 3, 42, 127], days <- [1, 7, 32] do
      weekdays = for day <- 1..7, Bitwise.band(mask, Bitwise.bsl(1, day - 1)) != 0, do: day
      schedule = F.schedule(c, %{"weekdays" => weekdays})
      first = Date.to_iso8601(start)
      until = Date.to_iso8601(Date.add(start, days)) <> "T00:00:00Z"

      query = %{
        "first_date" => first,
        "days" => days,
        "from" => first <> "T00:00:00Z",
        "until" => until
      }

      request = request(c, query, Calendar.UTCOnlyTimeZoneDatabase, schedule)
      assert {:ok, page} = Civil.page(request, c.time, c.limits)
      base = :calendar.date_to_gregorian_days({start.year, start.month, start.day})

      expected =
        for n <- 0..(days - 1),
            {y, m, d} = date <- [:calendar.gregorian_days_to_date(base + n)],
            :calendar.day_of_the_week(date) in weekdays,
            do:
              IO.iodata_to_binary(:io_lib.format(~c"~4..0B-~2..0B-~2..0B", [y, m, d])) <>
                "T09:00:00Z"

      assert Enum.map(page.occurrences, & &1["starts_at"]) == expected
      assert Civil.page(request, c.time, c.limits) == {:ok, page}
      split = first <> "T12:00:00Z"

      assert {:ok, left} =
               Civil.page(%{request | query: %{query | "until" => split}}, c.time, c.limits)

      assert {:ok, right} =
               Civil.page(%{request | query: %{query | "from" => split}}, c.time, c.limits)

      assert left.occurrences ++ right.occurrences == page.occurrences
    end
  end

  test "database context and schedule bind originals while query and clock do not", c do
    request = request(c)
    assert {:ok, page} = Civil.page(request, c.time, c.limits)
    [point] = page.occurrences
    changed = %{c.time | "clock_generation" => "clock:2"}
    assert {:ok, fresh} = Civil.page(request, changed, c.limits)
    assert hd(fresh.occurrences)["original"] == point["original"]
    program = F.program(c, c.schedule)

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Civil.event(page, point, program, changed, c.profile, c.limits)

    shifted = %{
      request
      | query: %{
          request.query
          | "first_date" => "2026-07-15",
            "days" => 1,
            "from" => "2026-07-15T00:00:00Z"
        }
    }

    assert {:ok, %{occurrences: [^point]}} = Civil.page(shifted, c.time, c.limits)
    assert {:ok, one} = Civil.page(%{request | database: provider("zero-a")}, c.time, c.limits)
    assert {:ok, two} = Civil.page(%{request | database: provider("zero-b")}, c.time, c.limits)
    assert coordinates(one) == coordinates(two)
    refute hd(one.occurrences)["original"] == hd(two.occurrences)["original"]
    refute hd(one.occurrences)["database_basis"] == hd(two.occurrences)["database_basis"]
    refute inspect(one.occurrences) =~ "zero-a"

    assert {:error, %Error{code: :stale_civil_page}} =
             Civil.to_map(%{one | request: %{one.request | database: provider("zero-b")}}, c.limits)

    for field <- ["time_zone_basis", "producer_basis"] do
      schedule = F.schedule(c, %{field => "sha256:" <> String.duplicate("9", 64)})
      assert {:ok, other} = Civil.page(%{request | schedule: schedule}, c.time, c.limits)
      refute hd(other.occurrences)["original"] == point["original"]
    end
  end

  test "actual maximum callback counts, whole-output bounds and late refusal", c do
    schedule =
      F.schedule(c, %{
        "weekdays" => Enum.to_list(1..7),
        "fold_policy" => "both",
        "time_zone" => "Synthetic/Folds"
      })

    query = %{
      "first_date" => "2024-01-01",
      "days" => 366,
      "from" => "2024-01-01T00:00:00Z",
      "until" => "2025-01-01T00:00:00Z"
    }

    request = request(c, query, provider("folds"), schedule)
    assert {:ok, page} = Civil.page(request, c.time, c.limits)
    assert length(page.occurrences) == 732
    assert Process.get({CivilArchiveProvider, "folds", :resolve}) == 366
    assert Process.get({CivilArchiveProvider, "folds", :localize}) == 732
    {:ok, small} = Limits.new(%{c.limits.data | "max_collection_size" => 64})
    assert {:error, %Error{code: :limit_or_json_error}} = Civil.page(request, c.time, small)
    ordinary = F.schedule(c, %{"weekdays" => Enum.to_list(1..7)})

    for context <- ["refuse", "late"] do
      request =
        request(
          c,
          %{
            "first_date" => "2026-07-13",
            "days" => 2,
            "from" => "2026-07-13T00:00:00Z",
            "until" => "2026-07-15T00:00:00Z"
          },
          provider(context),
          ordinary
        )

      assert {:error, %Error{code: :civil_refused} = error} = Civil.page(request, c.time, c.limits)
      refute inspect(error) =~ "PRIVATE_CIVIL_CANARY"

      if context == "late" do
        assert Process.get({CivilArchiveProvider, "late", :resolve}) == 2
        assert Process.get({CivilArchiveProvider, "late", :localize}) == 1
      end
    end
  end

  test "the first and final supported years preserve original coordinates", c do
    schedule = F.schedule(c, %{"weekdays" => Enum.to_list(1..7)})

    for {date, until} <- [
          {"0000-01-01", "0000-01-02T00:00:00Z"},
          {"9999-12-31", "9999-12-31T23:59:59Z"}
        ] do
      query = %{"first_date" => date, "days" => 1, "from" => date <> "T00:00:00Z", "until" => until}

      assert {:ok, %{occurrences: [point]}} =
               Civil.page(
                 request(c, query, Calendar.UTCOnlyTimeZoneDatabase, schedule),
                 c.time,
                 c.limits
               )

      assert point["nominal"] == date <> "T09:00:00"
      assert point["starts_at"] == date <> "T09:00:00Z"
    end
  end

  test "native immutable provider fields and context bytes are revalidated", c do
    good = provider("iana")
    assert {:ok, request} = CivilRequest.new(c.schedule, c.query, provider(<<>>), c.limits)
    assert {:ok, %{occurrences: [_]}} = Civil.page(request, c.time, c.limits)

    for db <- [Map.put(good, :extra, nil), %{good | context: :not_binary}, %{good | module: Civil}] do
      assert {:error, %Error{code: :invalid_civil_request}} =
               CivilRequest.new(c.schedule, c.query, db, c.limits)
    end

    {:ok, small} = Limits.new(%{c.limits.data | "max_bytes" => 16_384})

    assert {:error, %Error{code: :invalid_civil_request}} =
             CivilRequest.new(
               c.schedule,
               c.query,
               %{good | context: :binary.copy(<<0>>, 16_385)},
               small
             )
  end

  test "complete ambiguities retain literal originals, policies and filtered third positions", c do
    {:ok, db} = ExBooking.TimeZoneProvider.new(CompleteCivilArchiveProvider, <<3::16>>)
    schedule = F.schedule(c, %{"fold_policy" => "both", "time_zone" => "Synthetic/Multiple"})
    query = %{"days" => 1, "from" => "2026-07-13T00:00:00Z", "until" => "2026-07-14T00:00:00Z"}
    request = request(c, query, db, schedule)
    assert {:ok, page} = Civil.page(request, c.time, c.limits)

    assert Enum.map(page.occurrences, & &1["starts_at"]) ==
             ["2026-07-13T08:59:58Z", "2026-07-13T08:59:59Z", "2026-07-13T09:00:00Z"]

    assert Enum.map(page.occurrences, & &1["resolution"]) ==
             ["first_fold", "second_fold", ["fold", 3]]

    assert {:ok, wire} = Civil.to_map(page, c.limits)
    assert :ok == ExJsonSchema.Validator.validate(c.schema, wire)
    third = List.last(page.occurrences)

    assert {:ok, event} =
             Civil.event(page, third, F.program(c, schedule), c.time, c.profile, c.limits)

    assert event.data["original"] == third["original"]
    filtered = %{request | query: %{request.query | "from" => "2026-07-13T09:00:00Z"}}
    assert {:ok, %{occurrences: [^third]}} = Civil.page(filtered, c.time, c.limits)
    changed = %{c.time | "clock_generation" => "clock:2"}
    assert {:ok, fresh} = Civil.page(filtered, changed, c.limits)
    assert hd(fresh.occurrences)["original"] == third["original"]

    for {policy, expected} <- [
          {"first", "2026-07-13T08:59:58Z"},
          {"second", "2026-07-13T08:59:59Z"}
        ] do
      selected = F.schedule(c, Map.put(schedule, "fold_policy", policy))

      assert {:ok, %{occurrences: [point]}} =
               Civil.page(%{request | schedule: selected}, c.time, c.limits)

      assert point["starts_at"] == expected

      assert {:ok, %{occurrences: []}} =
               Civil.page(%{filtered | schedule: selected}, c.time, c.limits)
    end

    reject = F.schedule(c, Map.put(schedule, "fold_policy", "reject"))

    assert {:error, %Error{code: :civil_refused}} =
             Civil.page(%{filtered | schedule: reject}, c.time, c.limits)

    assert {:error, %Error{code: :stale_civil_page}} =
             Civil.to_map(%{page | occurrences: [third]}, c.limits)

    assert Process.get({CompleteCivilArchiveProvider, <<3::16>>, :legacy}, 0) == 0

    assert {:error, :time_zone_provider_refused} =
             ExBooking.TimeZoneProvider.from_naive(
               ~N[2026-07-13 09:00:00],
               "Synthetic/Multiple",
               db
             )
  end

  test "complete sets preserve the 732-point and total-work ceilings without partial output", c do
    schedule =
      F.schedule(c, %{
        "weekdays" => [1, 2],
        "fold_policy" => "both",
        "time_zone" => "Synthetic/Multiple"
      })

    query = %{"days" => 1, "from" => "2026-07-13T00:00:00Z", "until" => "2026-07-15T00:00:00Z"}
    {:ok, db} = ExBooking.TimeZoneProvider.new(CompleteCivilArchiveProvider, <<732::16>>)
    request = request(c, query, db, schedule)
    assert {:ok, page} = Civil.page(request, c.time, c.limits)
    base = DateTime.to_unix(~U[2026-07-13 09:00:00Z], :millisecond)

    assert Enum.map(page.occurrences, & &1["due_ms"]) ==
             for(index <- 1..732, do: base - (732 - index) * 1000)

    assert List.last(page.occurrences)["resolution"] == ["fold", 732]
    assert Process.get({CompleteCivilArchiveProvider, <<732::16>>, :localize}) == 732
    assert {:ok, wire} = Civil.to_map(page, c.limits)
    assert :ok == ExJsonSchema.Validator.validate(c.schema, wire)

    {:ok, exact} = ExBooking.TimeZoneProvider.new(CompleteCivilArchiveProvider, <<366::16>>)
    both_days = %{request | database: exact, query: %{request.query | "days" => 2}}
    assert {:ok, %{occurrences: points}} = Civil.page(both_days, c.time, c.limits)
    assert length(points) == 732
    assert Process.get({CompleteCivilArchiveProvider, <<366::16>>, :resolve}) == 2
    assert Process.get({CompleteCivilArchiveProvider, <<366::16>>, :localize}) == 732

    {:ok, over} = ExBooking.TimeZoneProvider.new(CompleteCivilArchiveProvider, <<367::16>>)
    limited = %{both_days | database: over}
    assert {:error, %Error{code: :civil_work_bound} = error} = Civil.page(limited, c.time, c.limits)
    assert Process.get({CompleteCivilArchiveProvider, <<367::16>>, :resolve}) == 2
    assert Process.get({CompleteCivilArchiveProvider, <<367::16>>, :localize}) == 367
    assert Process.get({CompleteCivilArchiveProvider, <<367::16>>, :legacy}, 0) == 0
    assert Civil.page(limited, c.time, c.limits) == {:error, error}
    first = F.schedule(c, Map.put(schedule, "fold_policy", "first"))

    assert {:error, %Error{code: :civil_work_bound}} =
             Civil.page(%{limited | schedule: first}, c.time, c.limits)

    {:ok, too_many} = ExBooking.TimeZoneProvider.new(CompleteCivilArchiveProvider, <<733::16>>)

    assert {:error, %Error{code: :civil_refused}} =
             Civil.page(%{request | database: too_many}, c.time, c.limits)

    assert Process.get({CompleteCivilArchiveProvider, <<733::16>>, :localize}, 0) == 0
  end

  defp provider(context) do
    {:ok, provider} = ExBooking.TimeZoneProvider.new(CivilArchiveProvider, context)
    provider
  end

  defp request(c, query \\ %{}, db \\ Calendar.UTCOnlyTimeZoneDatabase, schedule \\ nil) do
    {:ok, request} =
      CivilRequest.new(schedule || c.schedule, Map.merge(c.query, query), db, c.limits)

    request
  end

  defp coordinates(page),
    do: Enum.map(page.occurrences, &Map.take(&1, ~w(nominal starts_at resolution)))
end
