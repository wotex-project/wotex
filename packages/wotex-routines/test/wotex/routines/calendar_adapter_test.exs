defmodule Wotex.Routines.CalendarAdapterTest do
  @moduledoc false

  # Only adapter control flow is simulated here. Real producer semantics have
  # their separate extracted-archive lane. Synchronous execution and restoration
  # keep the selected published dependency's absence test intact.
  use ExUnit.Case, async: false

  alias Wotex.Routines.Calendar, as: Adapter
  alias Wotex.Routines.{CalendarRequest, Compiler, Error, Limits, Profile, Schedule}

  setup_all do
    Code.ensure_loaded!(ExBooking)
    {ExBooking, original, file} = :code.get_object_code(ExBooking)

    {_, diagnostics} =
      Code.with_diagnostics([log: false], fn ->
        Code.compile_string(
          """
          defmodule ExBooking do
            @moduledoc false

            def occurrences("work", _, _), do: {:error, {:limit, :occurrences, :work}}
            def occurrences("cursor", _, _), do: {:error, {:stale, :occurrences, :cursor_basis}}
            def occurrences("refuse", _, _), do: {:error, {:private, "PRIVATE_PRODUCER_CANARY"}}
            def occurrences("wrong", _, _), do: :unexpected
            def occurrences("raise", _, _), do: raise("PRIVATE_PRODUCER_CANARY")
            def occurrences(rule, start, options) do
              key = {Wotex.Routines.CalendarAdapterTest, :calls}
              Process.put(key, Process.get(key, 0) + 1)
              offset = if options[:cursor], do: options[:cursor].next_offset_days, else: 0
              values = for index <- offset..2 do
                utc = DateTime.add(start, index * 86400, :second, Calendar.UTCOnlyTimeZoneDatabase)
                %{__struct__: ExBooking.Occurrence, nominal: DateTime.to_naive(utc),
                  starts_at: utc, ordinal: index + 1, resolution: :unique}
              end
              values = Enum.filter(values, &(DateTime.compare(&1.starts_at, options[:from]) != :lt and DateTime.compare(&1.starts_at, options[:until]) == :lt))
              selected = Enum.take(values, options[:limit])
              next = if length(values) > length(selected),
                do: %{__struct__: ExBooking.OccurrenceCursor, basis: "fixture", next_offset_days: List.last(selected).ordinal, emitted_count: length(selected)},
                else: nil
              selected = case rule do
                "bad-list" -> nil
            "many" -> values
                "bad-order" -> Enum.reverse(selected)
                "bad-shape" -> [%{}]
                "bad-coordinate" -> [Map.put(hd(selected), :starts_at, nil)]
                "precision" -> [Map.update!(hd(selected), :starts_at, &%{&1 | microsecond: {1, 6}})]
                "bad-resolution" -> [Map.put(hd(selected), :resolution, :shifted)]
                _ -> selected
              end
              next = if rule == "bad-cursor", do: %{}, else: next
              %{__struct__: ExBooking.OccurrencePage, occurrences: selected, next_cursor: next}
              |> then(&{:ok, &1})
            end
          end
          """,
          "synthetic-adapter-producer.ex"
        )
      end)

    assert [%{severity: :warning, message: message}] = diagnostics
    assert String.contains?(message, "redefining module ExBooking")

    on_exit(fn ->
      :code.purge(ExBooking)
      :code.delete(ExBooking)
      {:module, ExBooking} = :code.load_binary(ExBooking, file, original)
    end)

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

    %{
      limits: limits,
      profile: profile,
      time: %{
        "epoch" => "boot:1",
        "elapsed_ms" => 1,
        "clock_generation" => "clock:1",
        "utc_low_ms" => nil,
        "utc_high_ms" => nil
      }
    }
  end

  test "adapter preserves bounded members, cursor and event identity under regeneration", c do
    request = request(c, "good", 1)
    assert {:ok, first} = Adapter.page(request, c.time, c.limits)
    assert {:ok, wire} = Adapter.to_map(first, c.limits)
    assert wire["has_more"]
    assert {:ok, second} = Adapter.page(%{request | cursor: first.next_cursor}, c.time, c.limits)
    assert hd(second.occurrences)["ordinal"] == 2
    assert hd(first.occurrences)["due_ms"] == 1_791_874_800_000

    assert {:error, %Error{code: :stale_calendar_page}} =
             Adapter.to_map(%{first | occurrences: []}, c.limits)

    program = program(c, request)

    assert {:ok, event} =
             Adapter.event(first, hd(first.occurrences), program, c.time, c.profile, c.limits)

    assert event.data["original"] == hd(first.occurrences)["original"]

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Adapter.event(
               first,
               hd(first.occurrences),
               program,
               %{c.time | "clock_generation" => "clock:2"},
               c.profile,
               c.limits
             )

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Adapter.event(first, hd(second.occurrences), program, c.time, c.profile, c.limits)
  end

  test "Time@2 calendar pages and cursors bind UTC generation and selected grammar", c do
    request = request(c, "good", 1)

    time =
      Map.merge(c.time, %{
        "format" => "wotex.routines.time@2",
        "utc_generation" => "utc:1",
        "utc_low_ms" => 0,
        "utc_high_ms" => 0
      })

    legacy = %{c.time | "clock_generation" => "utc:1"}
    {:ok, page} = Adapter.page(request, time, c.limits)
    {:ok, old} = Adapter.page(request, legacy, c.limits)
    assert page.time == time
    assert hd(page.occurrences)["original"] == hd(old.occurrences)["original"]
    assert hd(page.occurrences)["event"]["clock_generation"] == "utc:1"
    assert page.next_cursor.clock_generation == "utc:1"
    assert page.next_cursor.basis_digest != old.next_cursor.basis_digest
    continued = %{request | cursor: page.next_cursor}
    assert {:ok, _} = Adapter.page(continued, %{time | "clock_generation" => "elapsed:2"}, c.limits)

    assert {:error, %Error{code: :stale_calendar_cursor}} =
             Adapter.page(continued, %{time | "utc_generation" => "utc:2"}, c.limits)

    assert {:error, %Error{code: :stale_calendar_cursor}} =
             Adapter.page(continued, legacy, c.limits)

    assert {:error, %Error{code: :stale_calendar_cursor}} =
             Adapter.page(%{request | cursor: old.next_cursor}, time, c.limits)

    program = program(c, request)
    one = hd(page.occurrences)

    assert {:ok, _} =
             Adapter.event(
               page,
               one,
               program,
               %{time | "clock_generation" => "elapsed:2"},
               c.profile,
               c.limits
             )

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Adapter.event(
               page,
               one,
               program,
               %{time | "utc_generation" => "utc:2"},
               c.profile,
               c.limits
             )

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Adapter.event(page, one, program, legacy, c.profile, c.limits)
  end

  test "missing Time@2 UTC basis refuses before the calendar producer is called", c do
    time = Map.merge(c.time, %{"format" => "wotex.routines.time@2", "utc_generation" => nil})
    assert Process.get({__MODULE__, :calls}, 0) == 0

    assert {:error, %Error{code: :missing_utc_basis}} =
             Adapter.page(request(c, "good", 1), time, c.limits)

    assert Process.get({__MODULE__, :calls}, 0) == 0
  end

  test "foreign producer output and faults stay typed and payload free", c do
    for {rule, expected} <- [
          {"work", :recurrence_work_bound},
          {"cursor", :stale_calendar_cursor},
          {"refuse", :recurrence_refused},
          {"wrong", :producer_contract_error},
          {"raise", :producer_contract_error},
          {"many", :producer_contract_error},
          {"bad-list", :producer_contract_error},
          {"bad-shape", :producer_contract_error},
          {"bad-coordinate", :producer_contract_error},
          {"precision", :unsupported_temporal_precision},
          {"bad-resolution", :unsupported_value},
          {"bad-cursor", :producer_contract_error}
        ] do
      assert {:error, %Error{code: ^expected}} = Adapter.page(request(c, rule, 1), c.time, c.limits)
    end

    assert {:error, %Error{code: :producer_contract_error}} =
             Adapter.page(request(c, "bad-order", 3), c.time, c.limits)
  end

  defp program(c, request) do
    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "procedure",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => [],
      "trigger" => %{
        "kind" => "due",
        "schedule_id" => request.schedule["schedule_id"],
        "schedule_basis" => request.schedule["definition_digest"]
      },
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => %{"id" => "observe", "kind" => "noop"},
      "overlap" => "reject",
      "run_ms" => 1000
    }

    context = %{
      "registry" => [],
      "bases" => [],
      "bindings" => %{},
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, program} = Compiler.compile(source, context, c.profile, c.limits)

    program
  end

  defp request(c, rule, limit) do
    raw = %{
      "format" => "wotex.routines.schedule@1",
      "kind" => "calendar",
      "schedule_id" => "schedule:1",
      "definition_digest" => "sha256:" <> String.duplicate("0", 64),
      "late_window_ms" => 1000,
      "rule" => rule,
      "dtstart" => "2026-10-13T07:00:00Z",
      "time_zone" => "Etc/UTC",
      "time_zone_basis" => "sha256:" <> String.duplicate("6", 64),
      "producer_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, digest} = Schedule.semantic_digest(raw, c.limits)
    {:ok, schedule} = Schedule.new(%{raw | "definition_digest" => digest}, c.limits)

    {:ok, request} =
      CalendarRequest.new(
        schedule,
        %{
          "from" => "2026-10-13T00:00:00Z",
          "until" => "2026-10-17T00:00:00Z",
          "limit" => limit,
          "work_limit" => 10
        },
        Calendar.UTCOnlyTimeZoneDatabase,
        nil,
        c.limits
      )

    request
  end
end
