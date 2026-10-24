Code.require_file("decision_inputs.exs", __DIR__)
Code.require_file("decision_journal_oracle.exs", __DIR__)

defmodule DecisionJournalTimeConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias DecisionArchiveInputs, as: Input
  alias DecisionConsumerJournal, as: Oracle
  alias Wotex.Routines.{Basis, Decision, Error}

  @maximum 9_223_372_036_854_775_807

  for grammar <- [1, 2] do
    @tag time_grammar: grammar
    test "journal time #{grammar}: receipt, inclusive freshness and exclusive expiry partition every adjacent point",
         context do
      for grammar <- [context.time_grammar],
          {receipt, expiry, boundary} <- [{30, 2000, 30}, {10, 2000, 1011}, {10, 30, 30}],
          point <- neighbours(boundary) do
        c = base(grammar, sensor: true, elapsed: point)
        fact = %{c.corpus["fact"] | "receipt_ms" => receipt, "expires_ms" => expiry}
        member = compile(c)

        member = %{
          member
          | event: nil,
            snapshot: put_in(member.snapshot, ["facts", "measurement"], fact)
        }

        input = Input.input(c, [member, ready(c)])

        # These cuts come from the declared Fact and the independent ready member,
        # not from DecisionCell, compiled-tree traversal or returned Run records.
        frame = point(c, input, [receipt, receipt + 1001, expiry, point, point + 1000])
        elapsed_neighbours(frame, boundary)
        assert length(frame.collection.data["proposals"]) == 1
      end
    end

    @tag time_grammar: grammar
    test "journal time #{grammar}: uncertain source endpoints have independent cells on both sides of both thresholds",
         context do
      for grammar <- [context.time_grammar], low <- neighbours(2), high <- neighbours(997) do
        c = base(grammar, sensor: true, source: true, utc: {low, high})

        fact = %{
          c.corpus["fact"]
          | "receipt_ms" => 10,
            "expires_ms" => 2000,
            "source_time" => "1969-12-31T23:59:59.999999Z",
            "source_uncertainty_ms" => 3
        }

        member = compile(c)

        member = %{
          member
          | event: nil,
            snapshot: put_in(member.snapshot, ["facts", "measurement"], fact)
        }

        frame =
          point(c, Input.input(c, [member, ready(c)]), [10, 1011, 2000, 20, 1020], {[2], [997]})

        for now_low <- neighbours(2), now_high <- neighbours(997) do
          time = %{c.time | "utc_low_ms" => now_low, "utc_high_ms" => now_high}
          expected = same_side?(low, now_low, 2) and same_side?(high, now_high, 997)
          current(frame, time, expected)
        end

        relevant_identity(frame)
      end
    end

    @tag time_grammar: grammar
    test "journal time #{grammar}: signed fractional instants use literal floor expectations rather than datetime conversion",
         context do
      for grammar <- [context.time_grammar],
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
        member = compile(c)

        member = %{
          member
          | event: nil,
            snapshot: put_in(member.snapshot, ["facts", "measurement"], fact)
        }

        frame = point(c, Input.input(c, [member]), [10, 1011, 1010], {[center], [center + 1001]})
        assert frame.decision.data["cell"]["utc_low"]["min"] == center
        assert frame.decision.data["cell"]["utc_high"]["max"] == center + 1000
        current(frame, %{c.time | "utc_low_ms" => center, "utc_high_ms" => center + 1000}, true)
        current(frame, %{c.time | "utc_low_ms" => center - 1}, false)
        current(frame, %{c.time | "utc_high_ms" => center + 1001}, false)
      end
    end

    @tag time_grammar: grammar
    test "journal time #{grammar}: relevant absence and irrelevant UTC changes retain the selected Time grammar",
         context do
      for grammar <- [context.time_grammar], source <- [false, true], present <- [false, true] do
        c = base(grammar, source: source, utc: if(present, do: {0, 0}, else: nil))
        member = compile(c)
        member = %{member | event: nil}
        utc = if source, do: if(present, do: {[], []}, else: :absent), else: :ignored
        frame = point(c, Input.input(c, [member]), [], utc)

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

    @tag time_grammar: grammar
    test "journal time #{grammar}: retained delay wait and invocation starts survive their exact adjacent boundaries",
         context do
      for grammar <- [context.time_grammar], kind <- [:delay, :wait, :invoke] do
        c = base(grammar)
        member = temporal_member(c, kind)
        first = Input.collection(c, Input.input(c, [member]))
        retained = Input.retained(first)
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

    @tag time_grammar: grammar
    test "journal time #{grammar}: elapsed and UTC occurrence windows contribute even when the member emits nothing",
         context do
      for grammar <- [context.time_grammar], point <- [29, 30, 31, 39, 40, 41] do
        c = base(grammar, elapsed: point)
        member = occurrence(c, :elapsed, 30, 10)
        frame = point(c, Input.input(c, [member, ready(c)]), [point, point + 1000, 30, 40])
        elapsed_neighbours(frame, if(point < 30, do: 30, else: 40))
      end

      for grammar <- [context.time_grammar], low <- neighbours(90), high <- neighbours(120) do
        c = base(grammar, utc: {low, high})
        member = occurrence(c, :utc, 90, 30)
        frame = point(c, Input.input(c, [member, ready(c)]), [20, 1020], {[90], [120]})

        for now_low <- neighbours(90), now_high <- neighbours(120) do
          current(
            frame,
            %{c.time | "utc_low_ms" => now_low, "utc_high_ms" => now_high},
            same_side?(low, now_low, 90) and same_side?(high, now_high, 120)
          )
        end
      end
    end

    @tag time_grammar: grammar
    test "journal time #{grammar}: reported edges preserve prior debounce and after cooldown including zero debounce",
         context do
      for grammar <- [context.time_grammar], debounce <- [0, 7] do
        c = base(grammar, sensor: true)

        trigger = %{
          "kind" => "edge",
          "binding" => "measurement",
          "direction" => "rising",
          "debounce_ms" => debounce,
          "cooldown_ms" => 40,
          "hysteresis" => %{"enter" => 2500, "exit" => 1500}
        }

        member = compile(c, %{"trigger" => trigger})
        first = Input.collection(c, Input.input(c, [sample(member, 1, 20, 1000)]))
        edge = hd(first.data["transitions"])["result"]["edge"]
        candidate = sample(member, 2, 30, 3000)
        input = Input.input(%{c | time: candidate.time}, [candidate])
        input = put_in(input, ["entries", Access.at(0), "prior", "edge"], edge)
        second = Input.collection(c, input)

        if debounce == 0 do
          frame = point(%{c | time: candidate.time}, input, [20, 30, 70, 1030, 1031])
          elapsed_neighbours(frame, 70)
        else
          edge = hd(second.data["transitions"])["result"]["edge"]

          for now <- neighbours(37) do
            sample = sample(member, 3, now, 3000)
            input = Input.input(%{c | time: sample.time}, [sample, ready(%{c | time: sample.time})])
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

    @tag time_grammar: grammar
    test "journal time #{grammar}: prior history and independently shorter effect deadlines remain cuts after expiry",
         context do
      for grammar <- [context.time_grammar] do
        c = base(grammar)
        member = compile(c, %{"run_ms" => 20_000})
        first = Input.collection(c, Input.input(c, [member]))

        for now <- [15_019, 15_020, 15_021, 20_019, 20_020, 20_021] do
          c = %{c | time: %{c.time | "elapsed_ms" => now}}
          retained = Input.retained(first)
          frame = point(c, %{retained | "time" => c.time}, [20, now, 15_020, 20_020])
          current(frame, c.time, true)
        end

        terminal =
          compile(base(grammar, elapsed: 50), %{"steps" => %{"id" => "done", "kind" => "noop"}})

        completed = Input.collection(terminal, Input.input(terminal, [terminal]))
        run = hd(completed.data["transitions"])["result"]["run"]

        for now <- neighbours(50), slot <- ~w(original busy) do
          c = %{terminal | time: %{terminal.time | "elapsed_ms" => now}, event: nil}
          input = Input.input(c, [c])
          input = put_in(input, ["entries", Access.at(0), "prior", slot], run)
          frame = point(c, input, [50, 1050])
          assert hd(frame.collection.data["transitions"])["result"] == nil
          elapsed_neighbours(frame, 50)
        end
      end
    end

    @tag time_grammar: grammar
    test "journal time #{grammar}: 65-bit intermediates are discarded at the chosen integer domains without wrapping",
         context do
      for grammar <- [context.time_grammar], now <- [0, @maximum - 1, @maximum] do
        c = base(grammar, sensor: true, elapsed: now)
        fact = %{c.corpus["fact"] | "receipt_ms" => @maximum - 2, "expires_ms" => @maximum}
        member = compile(c)

        member = %{
          member
          | event: nil,
            snapshot: put_in(member.snapshot, ["facts", "measurement"], fact)
        }

        frame = point(c, Input.input(c, [member]), [@maximum - 2, @maximum + 999, @maximum])
        elapsed_neighbours(frame, @maximum)
      end

      for grammar <- [context.time_grammar], center <- [-1, 1] do
        c = base(grammar, sensor: true, source: true, utc: {0, 0})

        source =
          if center == -1, do: "1969-12-31T23:59:59.999999Z", else: "1970-01-01T00:00:00.001001Z"

        fact = %{c.corpus["fact"] | "source_time" => source, "source_uncertainty_ms" => @maximum}
        member = compile(c)

        member = %{
          member
          | event: nil,
            snapshot: put_in(member.snapshot, ["facts", "measurement"], fact)
        }

        frame =
          point(
            c,
            Input.input(c, [member]),
            [10, 1010, 1011],
            {[center + @maximum], [center - @maximum + 1001]}
          )

        current(frame, %{c.time | "utc_low_ms" => @maximum, "utc_high_ms" => @maximum}, center == 1)
      end
    end
  end

  defp base(grammar, options \\ []) do
    c = Input.base()

    evidence =
      put_in(hd(c.corpus["bases"]), ["evidence", "require_source_time"], options[:source] == true)

    {:ok, digest} = Basis.semantic_digest(evidence, c.limits)

    corpus =
      c.corpus
      |> put_in(["fact", "profile_digest"], digest)
      |> put_in(["fact", "receipt_epoch"], c.time["epoch"])

    time = %{c.time | "elapsed_ms" => Keyword.get(options, :elapsed, 20)}
    time = if grammar == 1, do: Map.drop(time, ~w(format utc_generation)), else: time
    c = %{c | corpus: corpus, time: utc(time, Keyword.get(options, :utc, {0, 0}))}
    Map.merge(c, %{settings: options, definitions: []})
  end

  defp compile(c, changes \\ %{}) do
    Input.compile(c, Map.get(changes, "id", "clock:member"),
      sensor: c.settings[:sensor] == true,
      source_time: c.settings[:source] == true,
      definitions: c.definitions,
      steps: Map.get(changes, "steps", Input.effect()),
      condition: Map.get(changes, "condition", Input.literal(true)),
      run_ms: Map.get(changes, "run_ms", 1000),
      trigger: Map.get(changes, "trigger", %{"kind" => "manual"})
    )
  end

  defp sample(c, sequence, now, value), do: Input.sample(c, sequence, value, now)

  defp ready(c) do
    other = base(grammar(c.time), source: c.settings[:source] == true)
    compile(%{other | time: c.time}, %{"id" => "clock:independent-ready"})
  end

  defp temporal_member(c, :delay) do
    compile(c, %{
      "steps" => %{
        "id" => "sequence",
        "kind" => "sequence",
        "steps" => [
          %{"id" => "delay", "kind" => "delay", "duration_ms" => 7},
          %{"id" => "done", "kind" => "noop"}
        ]
      }
    })
  end

  defp temporal_member(c, :wait) do
    compile(c, %{
      "steps" => %{
        "id" => "wait",
        "kind" => "wait",
        "condition" => Input.literal(false),
        "timeout_ms" => 7
      }
    })
  end

  defp temporal_member(c, :invoke) do
    child =
      compile(c, %{"id" => "clock:child", "condition" => Input.literal(false), "run_ms" => 7}).source

    compile(%{c | definitions: [child]}, %{
      "steps" => %{
        "id" => "call",
        "kind" => "invoke",
        "routine_id" => "clock:child",
        "revision" => "1",
        "arguments" => %{}
      }
    })
  end

  defp occurrence(c, axis, due, late) do
    kind = if axis == :elapsed, do: "countdown", else: "due"
    trigger = %{"kind" => kind, "schedule_id" => "schedule:1", "schedule_basis" => digest()}
    member = compile(c, %{"trigger" => trigger})

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

  # Independent intersection of every recorded boundary's containing half-line.
  defp partition(value, cuts, minimum, maximum) do
    Enum.reduce(cuts, %{"min" => minimum, "max" => maximum}, fn boundary, interval ->
      cond do
        boundary < minimum or boundary > maximum -> interval
        value < boundary -> %{interval | "max" => min(interval["max"], boundary - 1)}
        true -> %{interval | "min" => max(interval["min"], boundary)}
      end
    end)
  end

  defp point(c, input, elapsed_cuts, utc_cuts \\ :ignored) do
    collection = Input.collection(c, input)
    assert :ok == Decision.verify_point(input, collection, c.profile, c.limits)
    decision = Input.decision(c, collection)
    expected = cell(c.time, elapsed_cuts, utc_cuts)
    assert decision.data["cell"] === expected
    assert {:ok, projected} = Decision.to_map(decision, c.profile, c.limits)
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
      "arbitration" =>
        Oracle.arbitrate(
          collection.data["proposals"],
          dispositions,
          1,
          collection.data["collection_digest"]
        )
    }

    frame = %{c: c, collection: collection, decision: decision, context: context, cell: expected}
    current(frame, c.time, true)
    frame
  end

  defp cell(time, elapsed_cuts, utc_cuts) do
    elapsed = partition(time["elapsed_ms"], elapsed_cuts, 0, @maximum)
    elapsed = %{elapsed | "min" => time["elapsed_ms"]}

    mode =
      case utc_cuts do
        :ignored -> "ignored"
        :absent -> "absent"
        _ -> "present"
      end

    generation =
      if mode == "ignored",
        do: nil,
        else: time["utc_generation"] || if(grammar(time) == 1, do: time["clock_generation"])

    {low, high} =
      case utc_cuts do
        {low, high} ->
          {partition(time["utc_low_ms"], low, -@maximum, @maximum),
           partition(time["utc_high_ms"], high, -@maximum, @maximum)}

        _ ->
          {nil, nil}
      end

    %{
      "format" => "wotex.routines.time-cell@1",
      "time_format" => "wotex.routines.time@#{grammar(time)}",
      "epoch" => time["epoch"],
      "clock_generation" => time["clock_generation"],
      "utc_generation" => generation,
      "utc_mode" => mode,
      "elapsed" => elapsed,
      "utc_low" => low,
      "utc_high" => high
    }
  end

  defp elapsed_neighbours(frame, boundary) do
    limits = frame.cell["elapsed"]

    for now <- neighbours(boundary), now >= 0 and now <= @maximum do
      current(
        frame,
        %{frame.c.time | "elapsed_ms" => now},
        now >= limits["min"] and now <= limits["max"]
      )
    end
  end

  defp current(frame, time, valid) do
    context = put_in(frame.context, ["input", "time"], time)

    for decision <- [frame.decision, frame.decision.data] do
      result = Decision.check(decision, context, frame.c.profile, frame.c.limits)

      if valid do
        assert {:ok, checked} = result
        assert checked["point_time"] === frame.c.time
        assert checked["checked_time"] === time
        assert checked["transitions"] === frame.collection.data["transitions"]
        assert checked["proposal_states"] === frame.collection.data["proposal_states"]
        assert checked["arbitration"] === frame.context["arbitration"]
      else
        assert {:error, %Error{code: :stale_decision_time}} = result
      end
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
    if grammar(time) == 2, do: %{time | "utc_generation" => if(bounds, do: "utc:one")}, else: time
  end

  defp other_grammar(%{"format" => _} = time), do: Map.drop(time, ~w(format utc_generation))

  defp other_grammar(time),
    do:
      Map.merge(time, %{
        "format" => "wotex.routines.time@2",
        "utc_generation" => if(time["utc_low_ms"], do: "utc:one")
      })

  defp grammar(time), do: if(time["format"], do: 2, else: 1)
  defp same_side?(a, b, boundary), do: a < boundary == b < boundary
  defp neighbours(value), do: [value - 1, value, value + 1]
  defp digest, do: "sha256:" <> String.duplicate("8", 64)
end
