Code.require_file("../../support/civil_fixtures.exs", __DIR__)

defmodule Wotex.Routines.CivilAdapterTest do
  @moduledoc false

  # Only adapter validation/control flow uses this synthetic producer. The
  # independent extracted-archive lane exercises actual SP.09 semantics.
  use ExUnit.Case, async: false
  alias Wotex.Routines.{Civil, CivilRequest, Error, Limits}
  alias Wotex.Routines.Test.CivilFixtures, as: F

  setup_all do
    Code.ensure_loaded!(ExBooking)
    {ExBooking, original, file} = :code.get_object_code(ExBooking)

    {_, diagnostics} =
      Code.with_diagnostics([log: false], fn ->
        Code.compile_string(
          """
          defmodule ExBooking do
            @moduledoc false

            def civil_occurrences(_, _, opts) do
              key = {Wotex.Routines.CivilAdapterTest, :calls}
              Process.put(key, Process.get(key, 0) + 1)
              Wotex.Routines.CivilAdapterTest.producer(Process.get({Wotex.Routines.CivilAdapterTest, :mode}, :good), opts)
            end
          end
          """,
          "synthetic-civil-producer.ex"
        )
      end)

    assert [%{severity: :warning, message: message}] = diagnostics
    assert String.contains?(message, "redefining module ExBooking")

    on_exit(fn ->
      :code.purge(ExBooking)
      :code.delete(ExBooking)
      {:module, ExBooking} = :code.load_binary(ExBooking, file, original)
    end)

    F.load()
  end

  @spec producer(term(), keyword()) :: term()
  def producer(:refuse, _), do: {:error, {:private, "PRIVATE_CIVIL_CANARY"}}
  def producer(:wrong, _), do: :unexpected
  def producer(:work, _), do: {:error, {:limit, :civil_occurrences, :work}}
  def producer(:other_limit, _), do: {:error, {:limit, :civil_occurrences, :other}}

  def producer({:folds, resolutions}, opts) do
    values =
      for {resolution, index} <- Enum.with_index(resolutions, 1),
          instant = DateTime.add(~U[2026-07-13 09:00:00Z], index - length(resolutions)),
          DateTime.compare(instant, opts[:from]) != :lt,
          DateTime.compare(instant, opts[:until]) == :lt,
          do: %{
            __struct__: ExBooking.CivilOccurrence,
            nominal: ~N[2026-07-13 09:00:00],
            starts_at: instant,
            resolution: resolution
          }

    {:ok, values}
  end

  def producer(:raise, _), do: raise("PRIVATE_CIVIL_CANARY")

  def producer(:undef, _),
    do: raise(UndefinedFunctionError, module: UnknownProducer, function: :private_canary, arity: 0)

  def producer(mode, opts) do
    values =
      for instant <- [~U[2026-07-13 09:00:00Z], ~U[2026-07-15 09:00:00Z]],
          DateTime.compare(instant, opts[:from]) != :lt,
          DateTime.compare(instant, opts[:until]) == :lt,
          do: %{
            __struct__: ExBooking.CivilOccurrence,
            nominal: DateTime.to_naive(instant),
            starts_at: instant,
            resolution: :unique
          }

    {:ok, selected(mode, values)}
  end

  defp selected(:empty, _), do: []
  defp selected(:improper, [first | _]), do: [first | :improper]
  defp selected(:many, [first | _]), do: List.duplicate(first, 733)
  defp selected(:duplicate, [first | _]), do: [first, first]
  defp selected(:extra, [first | _]), do: [Map.put(first, :extra, nil)]
  defp selected(:missing, [first | _]), do: [Map.delete(first, :nominal)]

  defp selected(:bad_date, [first | _]),
    do: [put_in(first, [Access.key(:nominal), Access.key(:month)], 13)]

  defp selected(:bad_zone, [first | _]),
    do: [put_in(first, [Access.key(:starts_at), Access.key(:time_zone)], "UTC")]

  defp selected(:offset, [first | _]),
    do: [put_in(first, [Access.key(:starts_at), Access.key(:utc_offset)], 1)]

  defp selected(:precision, [first | _]),
    do: [put_in(first, [Access.key(:starts_at), Access.key(:microsecond)], {1, 6})]

  defp selected(:milliseconds, [first | _]),
    do: [put_in(first, [Access.key(:starts_at), Access.key(:microsecond)], {1000, 6})]

  defp selected(:outside, [first | _]),
    do: [Map.put(first, :starts_at, ~U[2027-01-01 00:00:00Z])]

  defp selected(:nominal, [first | _]),
    do: [Map.put(first, :nominal, ~N[2026-07-14 09:00:00])]

  defp selected(:resolution, [first | _]), do: [Map.put(first, :resolution, :shifted)]
  defp selected(:late, [first | _]), do: [first, %{}]
  defp selected(:reverse, values), do: Enum.reverse(values)
  defp selected(_, values), do: values

  test "Time@2 civil projections retain UTC generation independently of elapsed changes", c do
    request = request(c)

    time =
      Map.merge(c.time, %{
        "format" => "wotex.routines.time@2",
        "utc_generation" => "utc:1",
        "utc_low_ms" => 0,
        "utc_high_ms" => 0
      })

    legacy = %{c.time | "clock_generation" => "utc:1"}
    {:ok, page} = Civil.page(request, time, c.limits)
    {:ok, old} = Civil.page(request, legacy, c.limits)
    one = hd(page.occurrences)
    assert page.time == time
    assert one["event"]["clock_generation"] == "utc:1"
    assert one["original"] == hd(old.occurrences)["original"]
    program = F.program(c, c.schedule)

    assert {:ok, _} =
             Civil.event(
               page,
               one,
               program,
               %{time | "clock_generation" => "elapsed:2"},
               c.profile,
               c.limits
             )

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Civil.event(
               page,
               one,
               program,
               %{time | "utc_generation" => "utc:2"},
               c.profile,
               c.limits
             )

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Civil.event(page, one, program, legacy, c.profile, c.limits)

    assert {:ok, fresh} = Civil.page(request, %{time | "utc_generation" => "utc:2"}, c.limits)
    assert hd(fresh.occurrences)["original"] == one["original"]
  end

  test "missing Time@2 UTC basis refuses before the civil producer is called", c do
    time = Map.merge(c.time, %{"format" => "wotex.routines.time@2", "utc_generation" => nil})
    assert Process.get({__MODULE__, :calls}, 0) == 0
    assert {:error, %Error{code: :missing_utc_basis}} = Civil.page(request(c), time, c.limits)
    assert Process.get({__MODULE__, :calls}, 0) == 0
  end

  test "checked JSON and events regenerate, preserve originals and bind current programs", c do
    request = request(c)
    assert {:ok, page} = Civil.page(request, c.time, c.limits)
    assert [one] = page.occurrences
    assert Map.take(one, ~w(nominal starts_at resolution)) == hd(c.vector["expected"])
    refute Map.has_key?(one, "ordinal")
    assert {:ok, wire} = Civil.to_map(page, c.limits)
    assert Map.keys(wire) == ["occurrences"]
    for value <- [wire, one], do: assert(:ok == ExJsonSchema.Validator.validate(c.schema, value))
    assert {:error, _} = ExJsonSchema.Validator.validate(c.schema, Map.put(one, "ordinal", 1))
    program = F.program(c, c.schedule)
    assert {:ok, event} = Civil.event(page, one, program, c.time, c.profile, c.limits)
    assert event.data["original"] == one["original"]
    assert event.data["program_digest"] == program.data["ir_digest"]
    changed = %{c.time | "clock_generation" => "clock:2"}

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Civil.event(page, one, program, changed, c.profile, c.limits)

    assert {:ok, fresh} = Civil.page(request, changed, c.limits)
    assert hd(fresh.occurrences)["original"] == one["original"]
    assert hd(fresh.occurrences)["event"]["clock_generation"] == "clock:2"

    shifted = %{
      request
      | query: %{
          request.query
          | "first_date" => "2026-07-15",
            "days" => 1,
            "from" => "2026-07-15T00:00:00Z"
        }
    }

    assert {:ok, overlap} = Civil.page(shifted, c.time, c.limits)
    assert hd(overlap.occurrences) == one
    changed_schedule = F.schedule(c, %{"late_window_ms" => 2000})
    assert {:ok, other} = Civil.page(%{request | schedule: changed_schedule}, c.time, c.limits)
    refute hd(other.occurrences)["original"] == one["original"]
    other_program = F.program(c, changed_schedule)

    assert {:error, %Error{code: :schedule_program_mismatch}} =
             Civil.event(page, one, other_program, c.time, c.profile, c.limits)

    assert {:error, %Error{code: :stale_temporal_projection}} =
             Civil.event(
               page,
               Map.put(one, "original", "forged"),
               program,
               c.time,
               c.profile,
               c.limits
             )

    assert {:error, %Error{code: :stale_civil_page}} =
             Civil.to_map(%{page | occurrences: []}, c.limits)

    assert {:error, %Error{code: :invalid_civil_page}} =
             Civil.to_map(Map.put(page, :extra, nil), c.limits)

    assert {:error, %Error{}} = Civil.event(page, one, program, %{}, c.profile, c.limits)
  end

  test "malformed producer outcomes never become partial or privately detailed results", c do
    request = request(c, %{"from" => "2026-07-13T00:00:00Z"})

    for mode <- [
          :wrong,
          :raise,
          :undef,
          :improper,
          :many,
          :duplicate,
          :reverse,
          :extra,
          :missing,
          :bad_date,
          :bad_zone,
          :offset,
          :milliseconds,
          :outside,
          :nominal,
          :resolution,
          :late
        ] do
      Process.put({__MODULE__, :mode}, mode)

      assert {:error, %Error{code: :producer_contract_error}} =
               Civil.page(request, c.time, c.limits),
             inspect(mode)
    end

    Process.put({__MODULE__, :mode}, :precision)

    assert {:error, %Error{code: :unsupported_temporal_precision}} =
             Civil.page(request, c.time, c.limits)

    Process.put({__MODULE__, :mode}, :refuse)
    assert {:error, %Error{code: :civil_refused} = error} = Civil.page(request, c.time, c.limits)
    refute inspect(error) =~ "PRIVATE_CIVIL_CANARY"
    Process.put({__MODULE__, :mode}, :empty)
    assert {:ok, %{occurrences: []}} = Civil.page(request, c.time, c.limits)
  end

  test "invalid preflight invokes no producer and complete output obeys selected limits", c do
    request = request(c, %{"from" => "2026-07-13T00:00:00Z"})

    for value <- [
          %{request | query: Map.put(request.query, "days", 367)},
          Map.put(request, :extra, nil),
          %{}
        ] do
      assert {:error, %Error{}} = Civil.page(value, c.time, c.limits)
    end

    assert Process.get({__MODULE__, :calls}, 0) == 0
    {:ok, small} = Limits.new(%{c.limits.data | "max_bytes" => 1400})
    assert {:error, %Error{code: :limit_or_json_error}} = Civil.page(request, c.time, small)
    {:ok, small_integer} = Limits.new(%{c.limits.data | "max_integer" => 1000})
    assert {:error, %Error{code: :integer_overflow}} = Civil.page(request, c.time, small_integer)

    {:ok, due} =
      DateTime.from_iso8601("2026-07-15T09:00:00Z")
      |> then(fn {:ok, t, _} -> {:ok, DateTime.to_unix(t, :millisecond)} end)

    {:ok, small_window} = Limits.new(%{c.limits.data | "max_integer" => due + 999})
    assert {:error, %Error{code: :integer_overflow}} = Civil.page(request(c), c.time, small_window)
  end

  test "complete local fold positions project without renumbering and regenerate", c do
    Process.put({__MODULE__, :mode}, {:folds, [:first_fold, :second_fold, {:fold, 3}]})
    schedule = F.schedule(c, %{"fold_policy" => "both"})
    request = %{request(c, %{"from" => "2026-07-13T00:00:00Z"}) | schedule: schedule}
    assert {:ok, page} = Civil.page(request, c.time, c.limits)

    assert Enum.map(page.occurrences, & &1["resolution"]) ==
             ["first_fold", "second_fold", ["fold", 3]]

    assert {:ok, wire} = Civil.to_map(page, c.limits)
    assert :ok == ExJsonSchema.Validator.validate(c.schema, wire)
    third = List.last(page.occurrences)
    filtered = %{request | query: %{request.query | "from" => "2026-07-13T09:00:00Z"}}
    assert {:ok, %{occurrences: [^third]}} = Civil.page(filtered, c.time, c.limits)
    program = F.program(c, schedule)
    assert {:ok, event} = Civil.event(page, third, program, c.time, c.profile, c.limits)
    assert event.data["original"] == third["original"]

    for resolution <- [["fold", 2], ["fold", 733], ["fold", 3.5], ["fold", 3, 4]] do
      assert {:error, _} =
               ExJsonSchema.Validator.validate(c.schema, %{third | "resolution" => resolution})
    end
  end

  test "malformed or inconsistent local positions refuse the complete producer result", c do
    schedule = F.schedule(c, %{"fold_policy" => "both"})
    request = %{request(c, %{"from" => "2026-07-13T00:00:00Z"}) | schedule: schedule}

    for resolutions <- [
          [{:fold, 2}],
          [{:fold, 733}],
          [{:fold, 3.5}],
          [["fold", 3]],
          [{:fold, 3, 4}],
          [:first_fold, :first_fold],
          [{:fold, 4}, {:fold, 3}],
          [:unique, :second_fold],
          [:first_fold, :unique]
        ] do
      Process.put({__MODULE__, :mode}, {:folds, resolutions})

      assert {:error, %Error{code: :producer_contract_error}} =
               Civil.page(request, c.time, c.limits)
    end

    Process.put({__MODULE__, :mode}, {:folds, [:first_fold, {:fold, 732}]})
    assert {:ok, page} = Civil.page(request, c.time, c.limits)
    assert List.last(page.occurrences)["resolution"] == ["fold", 732]
    assert {:ok, wire} = Civil.to_map(page, c.limits)
    assert :ok == ExJsonSchema.Validator.validate(c.schema, wire)

    first = %{request | schedule: F.schedule(c, %{"fold_policy" => "first"})}
    assert {:error, %Error{code: :producer_contract_error}} = Civil.page(first, c.time, c.limits)
  end

  test "only the exact producer work limit has a distinct refusal and no implicit retry", c do
    request = request(c)
    Process.put({__MODULE__, :mode}, :work)
    assert {:error, %Error{code: :civil_work_bound} = error} = Civil.page(request, c.time, c.limits)
    assert Civil.page(request, c.time, c.limits) == {:error, error}
    assert Process.get({__MODULE__, :calls}) == 2
    Process.put({__MODULE__, :mode}, :other_limit)
    assert {:error, %Error{code: :civil_refused}} = Civil.page(request, c.time, c.limits)
  end

  defp request(c, changes \\ %{}) do
    {:ok, request} =
      CivilRequest.new(
        c.schedule,
        Map.merge(c.query, changes),
        Calendar.UTCOnlyTimeZoneDatabase,
        c.limits
      )

    request
  end
end
