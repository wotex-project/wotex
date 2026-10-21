Code.require_file("../../support/decision_fixtures.exs", __DIR__)
Code.require_file("../../support/decision_reference.exs", __DIR__)

defmodule Wotex.Routines.DecisionTimeMatrixTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Decision, Error}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F
  alias Wotex.Routines.Test.DecisionFixtures, as: D
  alias Wotex.Routines.Test.DecisionReference, as: Reference

  @maximum 9_223_372_036_854_775_807

  test "receipt, inclusive freshness and exclusive expiry partition every adjacent point" do
    for grammar <- [1, 2],
        {receipt, expiry, boundary} <- [{30, 2000, 30}, {10, 2000, 1011}, {10, 30, 30}],
        point <- neighbours(boundary) do
      c = base(grammar, sensor: true, elapsed: point)
      fact = %{c.corpus["fact"] | "receipt_ms" => receipt, "expires_ms" => expiry}
      member = F.compile(c)
      member = %{member | event: nil, snapshot: put_in(member.snapshot, ["facts", "sensor"], fact)}
      input = D.input(c, [member, ready(c)])

      # These cuts come from the declared Fact and the independent ready member,
      # not from DecisionCell, compiled-tree traversal or returned Run records.
      frame = point(c, input, [receipt, receipt + 1001, expiry, point, point + 1000])
      elapsed_neighbours(frame, boundary)
      assert length(frame.collection.data["proposals"]) == 1
    end
  end

  test "uncertain source endpoints have independent cells on both sides of both thresholds" do
    for grammar <- [1, 2], low <- neighbours(2), high <- neighbours(997) do
      c = base(grammar, sensor: true, source: true, utc: {low, high})

      fact = %{
        c.corpus["fact"]
        | "receipt_ms" => 10,
          "expires_ms" => 2000,
          "source_time" => "1969-12-31T23:59:59.999999Z",
          "source_uncertainty_ms" => 3
      }

      member = F.compile(c)
      member = %{member | event: nil, snapshot: put_in(member.snapshot, ["facts", "sensor"], fact)}
      frame = point(c, D.input(c, [member, ready(c)]), [10, 1011, 2000, 20, 1020], {[2], [997]})

      for now_low <- neighbours(2), now_high <- neighbours(997) do
        time = %{c.time | "utc_low_ms" => now_low, "utc_high_ms" => now_high}
        expected = same_side?(low, now_low, 2) and same_side?(high, now_high, 997)
        current(frame, time, expected)
      end

      relevant_identity(frame)
    end
  end

  test "signed fractional instants use literal floor expectations rather than datetime conversion" do
    for grammar <- [1, 2],
        {source, center} <- [
          {"1969-12-31T23:59:59.998999Z", -2},
          {"1969-12-31T23:59:59.999000Z", -1},
          {"1969-12-31T23:59:59.999999Z", -1},
          {"1970-01-01T00:00:00.000000Z", 0},
          {"1970-01-01T00:00:00.000001Z", 0},
          {"1970-01-01T00:00:00.001001Z", 1}
        ] do
      c = base(grammar, sensor: true, source: true, utc: {10, 20})
      fact = %{c.corpus["fact"] | "source_time" => source, "source_uncertainty_ms" => 0}
      member = F.compile(c)
      member = %{member | event: nil, snapshot: put_in(member.snapshot, ["facts", "sensor"], fact)}
      frame = point(c, D.input(c, [member]), [10, 1011, 1010], {[center], [center + 1001]})
      assert frame.decision.data["cell"]["utc_low"]["min"] == center
      assert frame.decision.data["cell"]["utc_high"]["max"] == center + 1000
      current(frame, %{c.time | "utc_low_ms" => center, "utc_high_ms" => center + 1000}, true)
      current(frame, %{c.time | "utc_low_ms" => center - 1}, false)
      current(frame, %{c.time | "utc_high_ms" => center + 1001}, false)
    end
  end

  test "relevant absence and irrelevant UTC changes retain the selected Time grammar" do
    for grammar <- [1, 2], source <- [false, true], present <- [false, true] do
      c = base(grammar, source: source, utc: if(present, do: {0, 0}, else: nil))
      member = F.compile(c)
      member = %{member | event: nil}
      utc = if source, do: if(present, do: {[], []}, else: :absent), else: :ignored
      frame = point(c, D.input(c, [member]), [], utc)

      for bounds <- [nil, {-100, 100}] do
        time = utc(c.time, bounds)
        current(frame, time, not source or present == (bounds != nil))
      end

      if grammar == 2 and present do
        time = %{c.time | "utc_generation" => "utc:replacement"}
        current(frame, time, not source)
      end

      for time <- [
            %{c.time | "epoch" => "boot:replacement"},
            %{c.time | "clock_generation" => "elapsed:replacement"},
            %{c.time | "elapsed_ms" => 19},
            other_grammar(c.time)
          ] do
        current(frame, time, false)
      end
    end
  end

  test "retained delay wait and invocation starts survive their exact adjacent boundaries" do
    for grammar <- [1, 2], kind <- [:delay, :wait, :invoke] do
      c = base(grammar)
      member = temporal_member(c, kind)
      first = D.collection(c, D.input(c, [member]))
      retained = D.retained(first)
      old = point(c, first.data["input"], [20, 27, 1020])
      elapsed_neighbours(old, 27)

      for now <- neighbours(27) do
        c = %{c | time: %{c.time | "elapsed_ms" => now}}
        frame = point(c, %{retained | "time" => c.time}, [20, 27, 1020, now])
        run = hd(frame.collection.data["transitions"])["result"]["run"]
        assert run["start_ms"] == 20
        assert hd(run["steps"])["started_ms"] == 20
        current(frame, c.time, true)
      end
    end
  end

  test "elapsed and UTC occurrence windows contribute even when the member emits nothing" do
    for grammar <- [1, 2], point <- [29, 30, 31, 39, 40, 41] do
      c = base(grammar, elapsed: point)
      member = occurrence(c, :elapsed, 30, 10)
      frame = point(c, D.input(c, [member, ready(c)]), [point, point + 1000, 30, 40])
      elapsed_neighbours(frame, if(point < 30, do: 30, else: 40))
    end

    for grammar <- [1, 2], low <- neighbours(90), high <- neighbours(120) do
      c = base(grammar, utc: {low, high})
      member = occurrence(c, :utc, 90, 30)
      frame = point(c, D.input(c, [member, ready(c)]), [20, 1020], {[90], [120]})

      for now_low <- neighbours(90), now_high <- neighbours(120) do
        current(
          frame,
          %{c.time | "utc_low_ms" => now_low, "utc_high_ms" => now_high},
          same_side?(low, now_low, 90) and same_side?(high, now_high, 120)
        )
      end
    end
  end

  test "reported edges preserve prior debounce and after cooldown including zero debounce" do
    for grammar <- [1, 2], debounce <- [0, 7] do
      c = base(grammar, sensor: true)

      trigger = %{
        "kind" => "edge",
        "binding" => "sensor",
        "direction" => "rising",
        "debounce_ms" => debounce,
        "cooldown_ms" => 40,
        "hysteresis" => %{"enter" => 2500, "exit" => 1500}
      }

      member = F.compile(c, %{"trigger" => trigger})
      first = D.collection(c, D.input(c, [F.sample(member, 1, 20, 1000)]))
      edge = hd(first.data["transitions"])["result"]["edge"]
      candidate = F.sample(member, 2, 30, 3000)
      input = D.input(%{c | time: candidate.time}, [candidate])
      input = put_in(input, ["entries", Access.at(0), "prior", "edge"], edge)
      second = D.collection(c, input)

      if debounce == 0 do
        frame = point(%{c | time: candidate.time}, input, [20, 30, 70, 1030, 1031])
        elapsed_neighbours(frame, 70)
      else
        edge = hd(second.data["transitions"])["result"]["edge"]

        for now <- neighbours(37) do
          sample = F.sample(member, 3, now, 3000)
          input = D.input(%{c | time: sample.time}, [sample, ready(%{c | time: sample.time})])
          input = put_in(input, ["entries", Access.at(0), "prior", "edge"], edge)
          cooldown = if now >= 37, do: now + 40, else: 0

          frame =
            point(%{c | time: sample.time}, input, [
              20,
              30,
              37,
              now,
              cooldown,
              now + 1000,
              now + 1001
            ])

          elapsed_neighbours(frame, if(now < 37, do: 37, else: cooldown))
        end
      end
    end
  end

  test "prior history and independently shorter effect deadlines remain cuts after expiry" do
    for grammar <- [1, 2] do
      c = base(grammar)
      member = F.compile(c, %{"run_ms" => 20_000})
      first = D.collection(c, D.input(c, [member]))

      for now <- [15_019, 15_020, 15_021, 20_019, 20_020, 20_021] do
        c = %{c | time: %{c.time | "elapsed_ms" => now}}
        retained = D.retained(first)
        frame = point(c, %{retained | "time" => c.time}, [20, now, 15_020, 20_020])
        current(frame, c.time, true)
      end

      terminal =
        F.compile(base(grammar, elapsed: 50), %{"steps" => %{"id" => "done", "kind" => "noop"}})

      completed = D.collection(terminal, D.input(terminal, [terminal]))
      run = hd(completed.data["transitions"])["result"]["run"]

      for now <- neighbours(50), slot <- ~w(original busy) do
        c = %{terminal | time: %{terminal.time | "elapsed_ms" => now}, event: nil}
        input = D.input(c, [c])
        input = put_in(input, ["entries", Access.at(0), "prior", slot], run)
        frame = point(c, input, [50, 1050])
        assert hd(frame.collection.data["transitions"])["result"] == nil
        elapsed_neighbours(frame, 50)
      end
    end
  end

  test "65-bit intermediates are discarded at the chosen integer domains without wrapping" do
    for grammar <- [1, 2], now <- [0, @maximum - 1, @maximum] do
      c = base(grammar, sensor: true, elapsed: now)
      fact = %{c.corpus["fact"] | "receipt_ms" => @maximum - 2, "expires_ms" => @maximum}
      member = F.compile(c)
      member = %{member | event: nil, snapshot: put_in(member.snapshot, ["facts", "sensor"], fact)}
      frame = point(c, D.input(c, [member]), [@maximum - 2, @maximum + 999, @maximum])
      elapsed_neighbours(frame, @maximum)
    end

    for grammar <- [1, 2], center <- [-1, 1] do
      c = base(grammar, sensor: true, source: true, utc: {0, 0})

      source =
        if center == -1, do: "1969-12-31T23:59:59.999999Z", else: "1970-01-01T00:00:00.001001Z"

      fact = %{c.corpus["fact"] | "source_time" => source, "source_uncertainty_ms" => @maximum}
      member = F.compile(c)
      member = %{member | event: nil, snapshot: put_in(member.snapshot, ["facts", "sensor"], fact)}

      frame =
        point(
          c,
          D.input(c, [member]),
          [10, 1010, 1011],
          {[center + @maximum], [center - @maximum + 1001]}
        )

      current(frame, %{c.time | "utc_low_ms" => @maximum, "utc_high_ms" => @maximum}, center == 1)
    end
  end

  defp base(grammar, options \\ []) do
    c = F.fixture(sensor: options[:sensor])
    c = if options[:source], do: c, else: D.elapsed(c)

    c =
      if options[:sensor] do
        digest = Enum.find(c.context["bases"], &(&1["id"] == "example.scalar"))["semantic_digest"]
        %{c | corpus: put_in(c.corpus, ["fact", "profile_digest"], digest)}
      else
        c
      end

    time = %{c.time | "elapsed_ms" => Keyword.get(options, :elapsed, 20)}

    time =
      if grammar == 2,
        do: Map.merge(time, %{"format" => "wotex.routines.time@2", "utc_generation" => "utc:1"}),
        else: time

    %{c | time: utc(time, Keyword.get(options, :utc, {0, 0}))}
  end

  defp ready(c) do
    other = base(if(c.time["format"], do: 2, else: 1))

    [member] =
      D.members(%{other | time: c.time}, [{"independent-ready", true, "independent-ready"}])

    member
  end

  defp temporal_member(c, :delay) do
    steps = %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [
        %{"id" => "delay", "kind" => "delay", "duration_ms" => 7},
        %{"id" => "done", "kind" => "noop"}
      ]
    }

    F.compile(c, %{"steps" => steps})
  end

  defp temporal_member(c, :wait),
    do:
      F.compile(c, %{
        "steps" => %{
          "id" => "wait",
          "kind" => "wait",
          "condition" => %{"op" => "literal", "value" => false},
          "timeout_ms" => 7
        }
      })

  defp temporal_member(c, :invoke) do
    child = %{
      c.source
      | "id" => "child",
        "condition" => %{"op" => "literal", "value" => false},
        "run_ms" => 7
    }

    c = %{c | context: %{c.context | "definitions" => [child]}}

    F.compile(c, %{
      "steps" => %{
        "id" => "call",
        "kind" => "invoke",
        "routine_id" => "child",
        "revision" => "1",
        "arguments" => %{}
      }
    })
  end

  defp occurrence(c, axis, due, late) do
    kind = if axis == :elapsed, do: "countdown", else: "due"
    trigger = %{"kind" => kind, "schedule_id" => "schedule:1", "schedule_basis" => digest()}
    member = F.compile(c, %{"trigger" => trigger})

    common = %{
      "schedule_id" => "schedule:1",
      "schedule_basis" => digest(),
      "late_window_ms" => late
    }

    event =
      if axis == :elapsed,
        do:
          Map.merge(common, %{
            "kind" => "elapsed_due",
            "due_elapsed_ms" => due,
            "epoch" => c.time["epoch"],
            "clock_generation" => c.time["clock_generation"],
            "time_basis" => digest()
          }),
        else:
          Map.merge(common, %{
            "kind" => "due",
            "due_ms" => due,
            "clock_generation" => c.time["utc_generation"] || c.time["clock_generation"],
            "time_zone_basis" => digest()
          })

    %{member | event: Map.merge(member.event, event)}
  end

  # Independent scalar partition oracle. Callers declare cuts from raw fixture
  # constants. It neither inspects execution trees/results nor imports any
  # production time-cell, qualification, transition or pending helper.
  defp partition(value, cuts, minimum, maximum) do
    cuts = Enum.filter(cuts, &(&1 >= minimum and &1 <= maximum))
    left = Enum.filter(cuts, &(&1 <= value))
    right = Enum.filter(cuts, &(&1 > value))

    %{
      "min" => Enum.max([minimum | left]),
      "max" => Enum.min([maximum | Enum.map(right, &(&1 - 1))])
    }
  end

  defp point(c, input, elapsed_cuts, utc_cuts \\ :ignored) do
    collection = D.collection(c, input)
    assert :ok == D.proof(fn -> Decision.verify_point(input, collection, c.profile, c.limits) end)
    decision = D.decision(c, collection)
    assert {:ok, projected} = D.proof(fn -> Decision.to_map(decision, c.profile, c.limits) end)
    elapsed = partition(c.time["elapsed_ms"], elapsed_cuts, 0, @maximum)
    elapsed = %{elapsed | "min" => c.time["elapsed_ms"]}

    mode =
      case utc_cuts do
        :ignored -> "ignored"
        :absent -> "absent"
        _ -> "present"
      end

    generation =
      if mode == "ignored",
        do: nil,
        else: c.time["utc_generation"] || if(grammar(c.time) == 1, do: c.time["clock_generation"])

    {low, high} =
      case utc_cuts do
        {low, high} ->
          {partition(c.time["utc_low_ms"], low, -@maximum, @maximum),
           partition(c.time["utc_high_ms"], high, -@maximum, @maximum)}

        _ ->
          {nil, nil}
      end

    expected = %{
      "format" => "wotex.routines.time-cell@1",
      "time_format" => "wotex.routines.time@#{grammar(c.time)}",
      "epoch" => c.time["epoch"],
      "clock_generation" => c.time["clock_generation"],
      "utc_generation" => generation,
      "utc_mode" => mode,
      "elapsed" => elapsed,
      "utc_low" => low,
      "utc_high" => high
    }

    assert decision.data["cell"] == expected
    assert projected === decision.data

    dispositions =
      Map.new(
        collection.data["proposals"],
        &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      )

    context = %{
      "input" => input,
      "dispositions" => dispositions,
      "batch_limit" => 1,
      "arbitration" => Reference.decide(collection.data, dispositions, 1)
    }

    frame = %{c: c, collection: collection, decision: decision, context: context}
    current(frame, c.time, true)
    frame
  end

  defp elapsed_neighbours(frame, boundary) do
    cell = frame.decision.data["cell"]["elapsed"]

    for now <- neighbours(boundary), now >= 0 and now <= @maximum do
      current(
        frame,
        %{frame.c.time | "elapsed_ms" => now},
        now >= cell["min"] and now <= cell["max"]
      )
    end
  end

  defp current(frame, time, valid) do
    context = put_in(frame.context, ["input", "time"], time)

    result =
      D.proof(fn -> Decision.check(frame.decision, context, frame.c.profile, frame.c.limits) end)

    if valid do
      assert {:ok, checked} = result
      assert checked["point_time"] === frame.c.time
      assert checked["checked_time"] === time
      assert checked["transitions"] === frame.collection.data["transitions"]
      assert checked["arbitration"] === frame.context["arbitration"]
    else
      assert {:error, %Error{code: :stale_decision_time}} = result
    end
  end

  defp relevant_identity(frame) do
    current(frame, utc(frame.c.time, nil), false)

    if grammar(frame.c.time) == 2,
      do: current(frame, %{frame.c.time | "utc_generation" => "utc:replacement"}, false)
  end

  defp utc(time, bounds) do
    {low, high} = bounds || {nil, nil}
    time = %{time | "utc_low_ms" => low, "utc_high_ms" => high}
    if grammar(time) == 2, do: %{time | "utc_generation" => if(bounds, do: "utc:1")}, else: time
  end

  defp other_grammar(%{"format" => _} = time), do: Map.drop(time, ~w(format utc_generation))

  defp other_grammar(time),
    do:
      Map.merge(time, %{
        "format" => "wotex.routines.time@2",
        "utc_generation" => if(time["utc_low_ms"], do: "utc:1")
      })

  defp grammar(time), do: if(time["format"], do: 2, else: 1)
  defp same_side?(a, b, boundary), do: a < boundary == b < boundary
  defp neighbours(value), do: [value - 1, value, value + 1]
  defp digest, do: "sha256:" <> String.duplicate("8", 64)
end
