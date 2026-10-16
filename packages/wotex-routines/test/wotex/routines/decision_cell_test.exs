Code.require_file("../../support/continuation_fixtures.exs", __DIR__)

defmodule Wotex.Routines.DecisionCellTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Basis, Collection, DecisionCell, Error, Limits, Time}
  alias Wotex.Routines.Test.ContinuationFixtures, as: F

  @maximum 9_223_372_036_854_775_807
  @empty %{"original" => nil, "busy" => nil, "edge" => nil}

  test "an empty complete set has exact domain bounds and no UTC dependency" do
    c = F.fixture()

    for time <- [c.time, time2(c.time), absent(time2(c.time))] do
      input = %{
        "format" => "wotex.routines.collection-input@2",
        "membership" => %{"generation" => "membership:1", "programs" => []},
        "entries" => [],
        "time" => time
      }

      {:ok, collection} = Collection.evaluate(input, c.profile, c.limits)
      {:ok, cell} = DecisionCell.derive(collection.data, c.limits)
      assert cell["elapsed"] == %{"min" => 20, "max" => @maximum}
      assert cell["utc_mode"] == "ignored"
      assert cell["utc_generation"] == nil
      assert cell["utc_low"] == nil
      assert cell["utc_high"] == nil
      assert :ok == DecisionCell.check(cell, time)
      assert :ok == DecisionCell.check(cell, %{time | "elapsed_ms" => @maximum})
    end
  end

  test "negative delayed membership contributes its boundary before another effect" do
    base = elapsed_fixture()
    time = %{absent(time2(base.time)) | "elapsed_ms" => 5}
    base = %{base | time: time}

    delay = %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [%{"id" => "delay", "kind" => "delay", "duration_ms" => 5}, F.effect("no")]
    }

    a = F.compile(base, %{"id" => "delayed", "steps" => delay, "run_ms" => 95})
    b = F.compile(base, %{"id" => "ready", "steps" => F.effect("yes", true), "run_ms" => 95})
    programs = [a.program.data["ir_digest"], b.program.data["ir_digest"]]
    input = input(a)

    input = %{
      input
      | "membership" => %{"generation" => "membership:1", "programs" => programs},
        "entries" => Enum.map([a, b], &entry(&1, programs, @empty, &1.event))
    }

    {:ok, collection} = Collection.evaluate(input, a.profile, a.limits)
    assert length(collection.data["proposals"]) == 1
    {:ok, cell} = DecisionCell.derive(collection.data, a.limits)
    assert cell["elapsed"] == %{"min" => 5, "max" => 9}
    assert cell["utc_mode"] == "ignored"
    assert :ok == DecisionCell.check(cell, %{time | "elapsed_ms" => 9})
    assert stale?(DecisionCell.check(cell, %{time | "elapsed_ms" => 10}))

    # Retain the inert point's actual starts and calculate again. The delay
    # completes at its original boundary rather than restarting at publication.
    next = retained(collection.data)
    next = %{next | "time" => %{time | "elapsed_ms" => 10}}
    {:ok, current} = Collection.evaluate(next, a.profile, a.limits)
    assert length(current.data["proposals"]) == 2
    assert Enum.all?(current.data["transitions"], &(&1["result"]["run"]["start_ms"] == 5))
  end

  test "wait and invocation deadlines include blocked and unstarted paths" do
    base = elapsed_fixture()

    wait = %{
      "id" => "wait",
      "kind" => "wait",
      "condition" => %{"op" => "literal", "value" => false},
      "timeout_ms" => 7
    }

    c = F.compile(base, %{"steps" => wait})
    {:ok, cell} = DecisionCell.derive(collection(c), c.limits)
    assert cell["elapsed"] == %{"min" => 20, "max" => 26}

    child = %{
      base.source
      | "id" => "child",
        "condition" => %{"op" => "literal", "value" => false},
        "run_ms" => 9
    }

    invoke = %{
      "id" => "call",
      "kind" => "invoke",
      "routine_id" => "child",
      "revision" => "1",
      "arguments" => %{}
    }

    c =
      F.compile(%{base | context: %{base.context | "definitions" => [child]}}, %{"steps" => invoke})

    {:ok, cell} = DecisionCell.derive(collection(c), c.limits)
    assert cell["elapsed"] == %{"min" => 20, "max" => 28}

    steps = %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [wait, %{"id" => "unstarted", "kind" => "delay", "duration_ms" => 1}]
    }

    c = F.compile(base, %{"steps" => steps})
    col = collection(c)
    assert List.last(hd(col["transitions"])["result"]["run"]["steps"])["started_ms"] == nil
    {:ok, cell} = DecisionCell.derive(col, c.limits)
    assert cell["elapsed"]["max"] == 26
  end

  test "all binding Facts contribute inclusive freshness and exclusive expiry cuts" do
    c = elapsed_fixture(sensor: true) |> F.compile()
    fact = %{c.corpus["fact"] | "receipt_ms" => 10, "expires_ms" => 2000}
    c = %{c | snapshot: put_in(c.snapshot, ["facts", "sensor"], fact)}
    col = collection(c, @empty, nil)
    {:ok, cell} = DecisionCell.derive(col, c.limits)
    assert cell["elapsed"] == %{"min" => 20, "max" => 1010}
    assert cell["utc_mode"] == "ignored"
    assert :ok == DecisionCell.check(cell, %{c.time | "elapsed_ms" => 1010})
    assert stale?(DecisionCell.check(cell, %{c.time | "elapsed_ms" => 1011}))

    for quality <- ~w(usable unknown stale invalid) do
      next =
        put_in(c.snapshot, ["facts", "sensor"], %{fact | "quality" => quality, "expires_ms" => 30})

      {:ok, cell} = DecisionCell.derive(collection(%{c | snapshot: next}, @empty, nil), c.limits)
      assert cell["elapsed"] == %{"min" => 20, "max" => 29}
    end
  end

  test "future receipt thresholds and missing optional source coordinates remain explicit" do
    c = elapsed_fixture(sensor: true) |> F.compile()

    fact = %{
      c.corpus["fact"]
      | "receipt_ms" => 30,
        "expires_ms" => 2000,
        "source_time" => nil,
        "source_time_trust" => "unknown",
        "source_uncertainty_ms" => nil
    }

    c = %{c | snapshot: put_in(c.snapshot, ["facts", "sensor"], fact)}
    {:ok, cell} = DecisionCell.derive(collection(c, @empty, nil), c.limits)
    assert cell["elapsed"] == %{"min" => 20, "max" => 29}
    assert stale?(DecisionCell.check(cell, %{c.time | "elapsed_ms" => 30}))
  end

  test "required source confidence has independent signed endpoint cells in both directions" do
    c = F.fixture(sensor: true) |> F.compile()

    c = %{
      c
      | time: time2(c.time),
        snapshot: put_in(c.snapshot, ["facts", "sensor"], c.corpus["fact"])
    }

    {:ok, cell} = DecisionCell.derive(collection(c, @empty, nil), c.limits)
    {:ok, instant, _} = DateTime.from_iso8601(c.corpus["fact"]["source_time"])
    center = DateTime.to_unix(instant, :millisecond)
    assert cell["utc_low"] == %{"min" => center + 10, "max" => @maximum}
    assert cell["utc_high"] == %{"min" => -@maximum, "max" => center + 990}
    assert cell["elapsed"]["max"] == 1009

    endpoints = %{c.time | "utc_low_ms" => center + 10, "utc_high_ms" => center + 990}
    assert :ok == DecisionCell.check(cell, endpoints)
    assert stale?(DecisionCell.check(cell, %{endpoints | "utc_low_ms" => center + 9}))
    assert stale?(DecisionCell.check(cell, %{endpoints | "utc_high_ms" => center + 991}))
    assert stale?(DecisionCell.check(cell, %{c.time | "utc_generation" => "utc:2"}))
    assert stale?(DecisionCell.check(cell, absent(c.time)))
  end

  test "relevant UTC absence binds the selected grammar even with nil Facts and events" do
    for grammar <- [1, 2] do
      c = F.fixture() |> F.compile()

      time =
        if grammar == 1,
          do: %{c.time | "utc_low_ms" => nil, "utc_high_ms" => nil},
          else: absent(time2(c.time))

      c = %{c | time: time}
      {:ok, cell} = DecisionCell.derive(collection(c, @empty, nil), c.limits)
      assert cell["utc_mode"] == "absent"
      assert cell["utc_generation"] == if(grammar == 1, do: "elapsed:1", else: nil)
      assert :ok == DecisionCell.check(cell, time)
      present = %{time | "utc_low_ms" => 0, "utc_high_ms" => 0}
      present = if grammar == 2, do: %{present | "utc_generation" => "utc:1"}, else: present
      assert stale?(DecisionCell.check(cell, present))
    end
  end

  test "a due root needs UTC even before an occurrence and retains its window endpoints" do
    base = elapsed_fixture()
    trigger = %{"kind" => "due", "schedule_id" => "schedule:1", "schedule_basis" => digest()}
    c = F.compile(base, %{"trigger" => trigger})
    c = %{c | time: absent(time2(c.time))}
    {:ok, absent_cell} = DecisionCell.derive(collection(c, @empty, nil), c.limits)
    assert absent_cell["utc_mode"] == "absent"

    time = %{time2(c.time) | "utc_low_ms" => 100, "utc_high_ms" => 110, "utc_generation" => "utc:1"}

    event = %{
      c.event
      | "kind" => "due"
    }

    event =
      Map.merge(event, %{
        "schedule_id" => "schedule:1",
        "schedule_basis" => digest(),
        "due_ms" => 90,
        "late_window_ms" => 30,
        "clock_generation" => "utc:1",
        "time_zone_basis" => digest()
      })

    c = %{c | time: time, event: event}
    first = collection(c)
    {:ok, cell} = DecisionCell.derive(first, c.limits)
    assert cell["utc_low"] == %{"min" => 90, "max" => @maximum}
    assert cell["utc_high"] == %{"min" => -@maximum, "max" => 119}
    assert :ok == DecisionCell.check(cell, %{time | "utc_low_ms" => 90, "utc_high_ms" => 119})
    assert stale?(DecisionCell.check(cell, %{time | "utc_high_ms" => 120}))

    resumed = retained(first)
    {:ok, resumed} = Collection.evaluate(resumed, c.profile, c.limits)
    assert DecisionCell.derive(resumed.data, c.limits) == {:ok, cell}
  end

  test "elapsed windows do not acquire a dependency on UTC" do
    base = elapsed_fixture()
    trigger = %{"kind" => "countdown", "schedule_id" => "schedule:1", "schedule_basis" => digest()}
    c = F.compile(base, %{"trigger" => trigger})
    time = time2(c.time)

    event =
      Map.merge(c.event, %{
        "kind" => "elapsed_due",
        "schedule_id" => "schedule:1",
        "schedule_basis" => digest(),
        "due_elapsed_ms" => 10,
        "late_window_ms" => 20,
        "epoch" => time["epoch"],
        "clock_generation" => time["clock_generation"],
        "time_basis" => digest()
      })

    c = %{c | time: time, event: event}
    {:ok, cell} = DecisionCell.derive(collection(c), c.limits)
    assert cell["elapsed"] == %{"min" => 20, "max" => 29}
    assert cell["utc_mode"] == "ignored"
    assert :ok == DecisionCell.check(cell, absent(time))
    assert :ok == DecisionCell.check(cell, %{time | "utc_generation" => "utc:2"})
    assert stale?(DecisionCell.check(cell, %{time | "elapsed_ms" => 30}))
  end

  test "before and after reported-edge records retain debounce and cooldown boundaries" do
    c = elapsed_fixture(sensor: true)

    trigger = %{
      "kind" => "edge",
      "binding" => "sensor",
      "direction" => "rising",
      "debounce_ms" => 20,
      "cooldown_ms" => 40,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    c = F.compile(c, %{"trigger" => trigger})
    first = collection(F.sample(c, 1, 20, 1000))
    edge = hd(first["transitions"])["result"]["edge"]
    next = F.sample(c, 2, 30, 3000)
    second = collection(next, %{@empty | "edge" => edge})
    {:ok, cell} = DecisionCell.derive(second, c.limits)
    assert cell["elapsed"] == %{"min" => 30, "max" => 49}

    edge = hd(second["transitions"])["result"]["edge"]
    next = F.sample(c, 3, 50, 3000)
    third = collection(next, %{@empty | "edge" => edge})
    {:ok, cell} = DecisionCell.derive(third, c.limits)
    assert cell["elapsed"] == %{"min" => 50, "max" => 89}
  end

  test "wide intermediates cannot wrap or invent a finite cut beyond the selected domain" do
    c = elapsed_fixture(sensor: true) |> F.compile()
    time = %{c.time | "elapsed_ms" => @maximum - 1}
    fact = %{c.corpus["fact"] | "receipt_ms" => @maximum - 2, "expires_ms" => @maximum}
    c = %{c | time: time, snapshot: put_in(c.snapshot, ["facts", "sensor"], fact)}
    {:ok, cell} = DecisionCell.derive(collection(c, @empty, nil), c.limits)
    assert cell["elapsed"] == %{"min" => @maximum - 1, "max" => @maximum - 1}
    assert stale?(DecisionCell.check(cell, %{time | "elapsed_ms" => @maximum}))
  end

  test "negative fractional source instants use the qualifier's signed millisecond floor" do
    c = F.fixture(sensor: true) |> F.compile()

    fact = %{
      c.corpus["fact"]
      | "source_time" => "1969-12-31T23:59:59.999999Z",
        "source_uncertainty_ms" => 0
    }

    time = %{time2(c.time) | "utc_low_ms" => 0, "utc_high_ms" => 0}
    c = %{c | time: time, snapshot: put_in(c.snapshot, ["facts", "sensor"], fact)}
    {:ok, cell} = DecisionCell.derive(collection(c, @empty, nil), c.limits)
    assert cell["utc_low"] == %{"min" => -1, "max" => @maximum}
    assert cell["utc_high"] == %{"min" => -@maximum, "max" => 999}
  end

  test "terminal original and busy history contribute even with an inert nil transition" do
    c = elapsed_fixture() |> F.compile(%{"steps" => %{"id" => "done", "kind" => "noop"}})
    first = collection(%{c | time: %{c.time | "elapsed_ms" => 50}})
    run = hd(first["transitions"])["result"]["run"]
    assert run["status"] == "completed"

    for prior <- [%{@empty | "original" => run}, %{@empty | "busy" => run}] do
      col = collection(c, prior, nil)
      assert hd(col["transitions"])["result"] == nil
      {:ok, cell} = DecisionCell.derive(col, c.limits)
      assert cell["elapsed"] == %{"min" => 20, "max" => 49}
    end
  end

  test "effect deadlines can be earlier than the root and remain distinct" do
    c = elapsed_fixture() |> F.compile(%{"run_ms" => 20_000})
    col = collection(c)
    run = hd(col["transitions"])["result"]["run"]
    assert run["deadline_ms"] == 20_020
    assert hd(run["steps"])["deadline_ms"] == 15_020
    {:ok, cell} = DecisionCell.derive(col, c.limits)
    assert cell["elapsed"] == %{"min" => 20, "max" => 15_019}
    assert stale?(DecisionCell.check(cell, %{c.time | "elapsed_ms" => 15_020}))
  end

  test "every member of the maximum complete pending set contributes its bounds" do
    base = elapsed_fixture()

    parallel = %{
      "id" => "all",
      "kind" => "parallel",
      "branches" =>
        Enum.map(0..3, fn group ->
          %{
            "id" => "group:#{group}",
            "kind" => "parallel",
            "branches" => Enum.map(0..3, &F.effect("effect:#{group}:#{&1}"))
          }
        end)
    }

    members =
      Enum.map(1..64, fn i ->
        F.compile(base, %{
          "id" => "member:#{i}",
          "steps" => parallel,
          "run_ms" => if(i == 64, do: 7, else: 1000)
        })
      end)

    programs = Enum.map(members, & &1.program.data["ir_digest"])
    c = hd(members)

    input = %{
      input(c)
      | "membership" => %{"generation" => "membership:1", "programs" => programs},
        "entries" => Enum.map(members, &entry(&1, programs, @empty, &1.event))
    }

    {:ok, col} = Collection.evaluate(input, c.profile, c.limits)
    assert length(col.data["proposals"]) == 1024
    {:ok, cell} = DecisionCell.derive(col.data, c.limits)
    assert cell["elapsed"] == %{"min" => 20, "max" => 26}
    assert stale?(DecisionCell.check(cell, %{c.time | "elapsed_ms" => 27}))
  end

  test "current grammar, elapsed identity and regression refuse without changing the cell" do
    c = elapsed_fixture() |> F.compile()
    c = %{c | time: time2(c.time)}
    {:ok, cell} = DecisionCell.derive(collection(c), c.limits)

    for time <- [
          Map.drop(c.time, ~w(format utc_generation)),
          %{c.time | "epoch" => "boot:2"},
          %{c.time | "clock_generation" => "elapsed:2"},
          %{c.time | "elapsed_ms" => 19}
        ] do
      assert {:ok, _} = Time.new(time, c.limits)
      assert stale?(DecisionCell.check(cell, time))
    end

    assert :ok == DecisionCell.check(cell, %{c.time | "utc_generation" => "utc:2"})
    assert :ok == DecisionCell.check(cell, absent(c.time))
  end

  test "selected output limits remain effective for the internal cell projection" do
    c = elapsed_fixture() |> F.compile()
    col = collection(c)
    {:ok, small} = Limits.new(%{c.limits.data | "max_bytes" => 1})
    assert {:error, %Error{code: :limit_or_json_error}} = DecisionCell.derive(col, small)
  end

  defp elapsed_fixture(options \\ []) do
    c = F.fixture(options)

    bases =
      Enum.map(c.context["bases"], fn basis ->
        basis = put_in(basis, ["evidence", "require_source_time"], false)
        {:ok, digest} = Basis.semantic_digest(basis, c.limits)
        %{basis | "semantic_digest" => digest}
      end)

    digests = Map.new(bases, &{&1["id"], &1["semantic_digest"]})

    registry =
      Enum.map(c.context["registry"], fn ref ->
        if Map.has_key?(digests, ref["id"]),
          do: %{ref | "semantic_digest" => digests[ref["id"]]},
          else: ref
      end)

    bindings =
      Map.new(c.context["bindings"], fn {name, binding} ->
        {name, put_in(binding, ["basis", "semantic_digest"], digests[binding["basis"]["id"]])}
      end)

    context = %{c.context | "bases" => bases, "registry" => registry, "bindings" => bindings}

    corpus =
      if options[:sensor],
        do: put_in(c.corpus, ["fact", "profile_digest"], digests["example.scalar"]),
        else: c.corpus

    %{c | context: context, corpus: corpus}
  end

  defp input(c, prior \\ @empty, event \\ :current) do
    event = if event == :current, do: c.event, else: event
    programs = [c.program.data["ir_digest"]]

    %{
      "format" => "wotex.routines.collection-input@2",
      "membership" => %{"generation" => "membership:1", "programs" => programs},
      "entries" => [entry(c, programs, prior, event)],
      "time" => c.time
    }
  end

  defp entry(c, programs, prior, event),
    do: %{
      "program" => c.program.data,
      "event" => event,
      "snapshot" => %{c.snapshot | "active_programs" => programs},
      "prior" => prior
    }

  defp collection(c, prior \\ @empty, event \\ :current) do
    {:ok, collection} = Collection.evaluate(input(c, prior, event), c.profile, c.limits)
    collection.data
  end

  defp retained(collection) do
    results = Map.new(collection["transitions"], &{&1["program_digest"], &1["result"]})

    update_in(collection["input"], ["entries"], fn entries ->
      Enum.map(entries, fn entry ->
        result = results[entry["program"]["ir_digest"]]
        run = result["run"]

        event = %{
          "kind" => "resume",
          "original" => run["original"],
          "program_digest" => run["program_digest"]
        }

        %{
          entry
          | "event" => event,
            "prior" => %{"original" => run, "busy" => nil, "edge" => result["edge"]}
        }
      end)
    end)
  end

  defp time2(time),
    do: Map.merge(time, %{"format" => "wotex.routines.time@2", "utc_generation" => "utc:1"})

  defp absent(time),
    do: %{time | "utc_low_ms" => nil, "utc_high_ms" => nil, "utc_generation" => nil}

  defp stale?({:error, %Error{code: :stale_decision_time}}), do: true
  defp stale?(_), do: false
  defp digest, do: "sha256:" <> String.duplicate("6", 64)
end
