defmodule ContinuationConsumerJournal do
  @moduledoc false

  @spec open(map(), map()) :: map()
  def open(snapshot, time),
    do: %{revision: 0, snapshot: snapshot, time: time, run: nil, edge: nil, charges: MapSet.new()}

  @spec replace(map(), map()) :: map()
  def replace(journal, changes) do
    journal
    |> Map.merge(changes)
    |> Map.put(:revision, journal.revision + 1)
  end

  @spec prior(map()) :: map()
  def prior(journal), do: %{"original" => journal.run, "busy" => nil, "edge" => journal.edge}

  @spec commit(map(), map()) :: {:ok, map()} | {:error, atom()}
  def commit(journal, candidate) do
    transition = candidate.transition
    basis = transition["basis"]
    previous = if journal.run, do: journal.run["spent"], else: []
    current = if transition["run"], do: transition["run"]["spent"], else: []

    cond do
      journal.revision != candidate.revision or basis["snapshot"] != journal.snapshot or
        basis["time"] != journal.time or basis["prior"] != prior(journal) ->
        {:error, :stale}

      Enum.any?(previous, &(&1 not in current)) ->
        {:error, :lost_charge}

      true ->
        {:ok,
         %{
           journal
           | revision: journal.revision + 1,
             run: transition["run"],
             edge: transition["edge"],
             charges: MapSet.union(journal.charges, MapSet.new(current))
         }}
    end
  end
end

defmodule ContinuationJournalConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ContinuationConsumerJournal, as: Journal
  alias Wotex.Routines.{Arbitration, Collection, Compiler, Error, Kernel, Limits, Profile}

  setup_all do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, limits} =
      Limits.new(%{
        "max_bytes" => 16_777_216,
        "max_depth" => 64,
        "max_nodes" => 500_000,
        "max_collection_size" => 4096,
        "max_string_bytes" => 65_536,
        "max_integer" => 9_223_372_036_854_775_807
      })

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
        "pending_work" => 256,
        "run_ms" => 86_400_000
      })

    {:ok, date, _} = DateTime.from_iso8601(corpus["fact"]["source_time"])
    utc = DateTime.to_unix(date, :millisecond) + 500

    time = %{
      "format" => "wotex.routines.time@2",
      "epoch" => "journal:incarnation",
      "elapsed_ms" => 50,
      "clock_generation" => "elapsed:journal",
      "utc_generation" => "utc:journal",
      "utc_low_ms" => utc,
      "utc_high_ms" => utc
    }

    %{corpus: corpus, limits: limits, profile: profile, time: time}
  end

  test "journal revalidation and restart preserve charges without inventing a handoff", base do
    c = make(base, "absolute")
    owner = Journal.open(c.snapshot, c.time)
    {owner, first} = stage(c, owner, signal(c, "manual"))
    assert length(first["proposals"]) == 1

    admission =
      signal(c, "admission", %{"path" => [], "ref" => "journal:charge", "outcome" => "held"})

    candidate = propose(c, owner, admission)
    changed = Journal.replace(owner, %{time: %{owner.time | "utc_generation" => "utc:correction"}})
    assert {:error, :stale} = Journal.commit(changed, candidate)
    assert MapSet.size(changed.charges) == 0
    {owner, held} = stage(c, changed, admission)
    assert MapSet.size(owner.charges) == 1
    owner = Journal.replace(owner, %{snapshot: property_snapshot(c, owner.snapshot)})

    match_event =
      signal(c, "satisfied", %{
        "path" => [],
        "ref" => "journal:match",
        "fact_id" => "journal:report",
        "report_contract" => Enum.at(base.corpus["bases"], 2)["evidence"]["report_contract"]
      })

    {owner, completed} = stage(c, owner, match_event)
    assert completed["outcome"] == "completed"
    assert completed["run"]["spent"] == held["run"]["spent"]
    assert MapSet.size(owner.charges) == 1
    assert hd(owner.run["steps"])["receipts"]["handoff"] == nil
    assert hd(owner.run["steps"])["receipts"]["reported_match"] == nil
    assert hd(owner.run["steps"])["receipts"]["satisfied"]["outcome"] == "matched"
    restored = JSON.decode!(JSON.encode!(owner.run))

    owner =
      Journal.replace(owner, %{
        run: restored,
        time: %{
          owner.time
          | "epoch" => "journal:restart",
            "utc_generation" => nil,
            "utc_low_ms" => nil,
            "utc_high_ms" => nil
        }
      })

    {replayed, result} = stage(c, owner, signal(c, "resume"))
    assert result["run"] == restored
    assert result["proposals"] == []
    assert replayed.charges == owner.charges

    assert {:error, %Error{code: :missing_original}} =
             Kernel.advance(
               c.program,
               signal(c, "resume"),
               c.snapshot,
               c.time,
               %{"original" => nil, "busy" => nil, "edge" => nil},
               c.profile,
               c.limits
             )
  end

  test "journal edge continuation follows elapsed time and keeps the old original and edge", base do
    trigger = %{
      "kind" => "edge",
      "binding" => "temperature",
      "direction" => "rising",
      "debounce_ms" => 0,
      "cooldown_ms" => 300,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    c = make(base, "edge", trigger: trigger, delay: true)
    owner = Journal.open(c.snapshot, c.time)
    {owner, baseline} = reported(c, owner, 1, 50, 1000)
    assert baseline["outcome"] == "no-edge"
    {owner, first} = reported(c, owner, 2, 100, 3000)
    assert first["outcome"] == "running"
    assert first["proposals"] == []
    original = owner.run["original"]
    old_edge = owner.edge

    owner =
      Journal.replace(owner, %{
        time: %{owner.time | "elapsed_ms" => 180, "utc_generation" => "utc:changed"}
      })

    resume = signal(c, "resume", %{"original" => original})
    {owner, ready} = stage(c, owner, resume)
    assert [%{"path" => [1]}] = ready["proposals"]
    assert owner.run["original"] == original
    assert owner.edge == old_edge
    assert owner.run["clock_generation"] == "elapsed:journal"
    assert MapSet.size(owner.charges) == 0

    assert Enum.map(owner.run["steps"], & &1["original"]) ==
             Enum.map(first["run"]["steps"], & &1["original"])
  end

  test "journal clock cuts retain elapsed work when UTC changes or loses confidence", base do
    members =
      Enum.map(~w(manual countdown due), fn kind ->
        trigger =
          if kind == "manual",
            do: %{"kind" => kind},
            else: %{"kind" => kind, "schedule_id" => kind, "schedule_basis" => digest()}

        c = make(base, kind, trigger: trigger, delay: true)
        %{c | event: due_event(c, kind)}
      end)

    assert {:ok, first} = Collection.evaluate(cut(base, members), base.profile, base.limits)
    corrected = %{base.time | "elapsed_ms" => 130, "utc_generation" => "utc:replacement"}
    absent = %{corrected | "utc_generation" => nil, "utc_low_ms" => nil, "utc_high_ms" => nil}

    for {time, reason} <- [{corrected, "clock_changed"}, {absent, "window_closed"}] do
      assert {:ok, current} =
               Collection.evaluate(%{next_cut(first) | "time" => time}, base.profile, base.limits)

      assert length(current.data["proposals"]) == 2
      runs = Map.new(current.data["transitions"], &{&1["result"]["run"]["original"], &1["result"]})
      assert runs["journal:manual"]["outcome"] == "running"
      assert runs["journal:countdown"]["outcome"] == "running"
      assert runs["journal:due"]["outcome"] == "expired"
      assert runs["journal:due"]["run"]["reason"] == reason
      assert {:ok, repeated} = Collection.evaluate(next_cut(current), base.profile, base.limits)
      assert repeated.data["proposals"] == current.data["proposals"]
      assert Enum.all?(repeated.data["transitions"], &(&1["result"]["proposals"] == []))
    end
  end

  test "a journal retains all 64 contributors and reservations before a 16-group cut", base do
    members =
      Enum.map(1..64, fn index ->
        make(base, "member:#{index}",
          target: if(index == 64, do: "grid:1", else: "grid:#{index}"),
          value: index == 64
        )
      end)

    assert {:ok, first} = Collection.evaluate(cut(base, members), base.profile, base.limits)
    assert length(first.data["proposals"]) == 64
    assert {:ok, decision} = choose(base, first)
    assert length(decision["selected"]) == 16
    assert Enum.count(decision["decisions"], &(&1["outcome"] == "conflict")) == 2

    selected =
      decision["selected"]
      |> List.flatten()
      |> MapSet.new(& &1["program_digest"])

    next =
      update_in(next_cut(first), ["entries"], fn entries ->
        Enum.map(entries, fn entry ->
          if MapSet.member?(selected, entry["program"]["ir_digest"]) do
            event =
              Map.merge(entry["event"], %{
                "kind" => "admission",
                "path" => [],
                "ref" => "charge:" <> entry["event"]["original"],
                "outcome" => "held"
              })

            %{entry | "event" => event}
          else
            entry
          end
        end)
      end)

    assert {:ok, held} = Collection.evaluate(next, base.profile, base.limits)
    assert held.data["proposals"] == first.data["proposals"]
    assert Enum.count(held.data["proposal_states"], &(&1["status"] == "reserved")) == 16

    ledger =
      held.data["transitions"]
      |> Enum.flat_map(& &1["result"]["run"]["spent"])
      |> MapSet.new()

    assert MapSet.size(ledger) == 16
    assert {:ok, repeated} = Collection.evaluate(next_cut(held), base.profile, base.limits)
    assert repeated.data["proposals"] == held.data["proposals"]

    after_ledger =
      repeated.data["transitions"]
      |> Enum.flat_map(& &1["result"]["run"]["spent"])
      |> MapSet.new()

    assert after_ledger == ledger
    assert {:ok, later} = choose(base, repeated)
    assert later["selected"] == decision["selected"]
    assert Enum.count(later["decisions"], &(&1["outcome"] == "conflict")) == 2
    assert Enum.count(later["decisions"], &(&1["outcome"] == "batch-deferred")) == 46
  end

  defp make(base, id, options \\ []) do
    basis = Enum.at(base.corpus["bases"], 2)
    target = Keyword.get(options, :target, "grid:shared")

    leaf = %{
      "id" => "set",
      "kind" => "effect",
      "binding" => "setpoint",
      "input" => Keyword.get(options, :value, false),
      "completion" => "reported_match"
    }

    steps =
      if options[:delay],
        do: %{
          "id" => "ordered",
          "kind" => "sequence",
          "steps" => [%{"id" => "settle", "kind" => "delay", "duration_ms" => 80}, leaf]
        },
        else: leaf

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => id,
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ~w(setpoint temperature),
      "trigger" => Keyword.get(options, :trigger, %{"kind" => "manual"}),
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => steps,
      "overlap" => "reject",
      "run_ms" => 1200
    }

    sensor = hd(base.corpus["bases"])

    context = %{
      "registry" => base.corpus["registry"],
      "bases" => base.corpus["bases"],
      "bindings" => %{
        "setpoint" => %{
          "basis" => Map.take(basis, ~w(id version semantic_digest)),
          "thing_id" => "urn:journal:" <> target,
          "resource_roles" => %{"target" => target}
        },
        "temperature" => %{
          "basis" => Map.take(sensor, ~w(id version semantic_digest)),
          "thing_id" => base.corpus["fact"]["thing_id"],
          "resource_roles" => %{}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => System.fetch_env!("WOTEX_ROUTINES_COMPILER_BASIS")
    }

    assert {:ok, program} = Compiler.compile(source, context, base.profile, base.limits)

    snapshot = %{
      "id" => "journal:cut",
      "membership_generation" => "journal:installed",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{
        ("urn:journal:" <> target) => 1,
        target => 1,
        base.corpus["fact"]["thing_id"] => 1
      },
      "binding_bases" => %{
        "setpoint" => %{
          "profile_digest" => basis["semantic_digest"],
          "source_id" => "actuator:journal",
          "source_epoch" => "connection:1",
          "source_time_basis" => base.corpus["fact"]["source_time_basis"]
        },
        "temperature" =>
          Map.take(base.corpus["fact"], ~w(profile_digest source_id source_epoch source_time_basis))
      },
      "facts" => %{"setpoint" => nil, "temperature" => nil}
    }

    c = Map.merge(base, %{program: program, snapshot: snapshot, id: id})
    Map.put(c, :event, signal(c, "manual"))
  end

  defp signal(c, kind, data \\ %{}),
    do:
      Map.merge(
        %{
          "kind" => kind,
          "original" => "journal:" <> c.id,
          "program_digest" => c.program.data["ir_digest"]
        },
        data
      )

  defp propose(c, owner, event) do
    assert {:ok, result} =
             Kernel.advance(
               c.program,
               event,
               owner.snapshot,
               owner.time,
               Journal.prior(owner),
               c.profile,
               c.limits
             )

    %{revision: owner.revision, transition: result}
  end

  defp stage(c, owner, event) do
    candidate = propose(c, owner, event)
    assert {:ok, changed} = Journal.commit(owner, candidate)
    {changed, candidate.transition}
  end

  defp reported(c, owner, sequence, elapsed, value) do
    fact =
      Map.merge(c.corpus["fact"], %{
        "id" => "journal:sample:#{sequence}",
        "sequence" => sequence,
        "receipt_epoch" => owner.time["epoch"],
        "receipt_ms" => elapsed,
        "expires_ms" => elapsed + 1000,
        "value" => value
      })

    owner =
      Journal.replace(owner, %{
        snapshot: put_in(owner.snapshot, ["facts", "temperature"], fact),
        time: %{owner.time | "elapsed_ms" => elapsed}
      })

    event =
      signal(c, "fact", %{
        "original" => "journal:edge:#{sequence}",
        "binding" => "temperature",
        "fact_id" => fact["id"]
      })

    stage(c, owner, event)
  end

  defp property_snapshot(c, snapshot) do
    fact =
      Map.merge(c.corpus["fact"], %{
        "id" => "journal:report",
        "thing_id" => c.program.data["context"]["bindings"]["setpoint"]["thing_id"],
        "affordance_name" => "fast",
        "value" => false,
        "unit" => nil,
        "source_id" => "actuator:journal",
        "profile_digest" => Enum.at(c.corpus["bases"], 2)["semantic_digest"],
        "receipt_epoch" => c.time["epoch"]
      })

    put_in(snapshot, ["facts", "setpoint"], fact)
  end

  defp cut(base, members) do
    digests = Enum.map(members, & &1.program.data["ir_digest"])

    %{
      "format" => "wotex.routines.collection-input@2",
      "membership" => %{"generation" => "journal:installed", "programs" => digests},
      "time" => base.time,
      "entries" =>
        Enum.map(
          members,
          &%{
            "program" => &1.program.data,
            "event" => &1.event,
            "snapshot" => %{&1.snapshot | "active_programs" => digests},
            "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
          }
        )
    }
  end

  defp next_cut(collection) do
    history = Map.new(collection.data["transitions"], &{&1["program_digest"], &1["result"]})

    update_in(collection.data["input"], ["entries"], fn entries ->
      Enum.map(entries, fn entry ->
        previous = history[entry["program"]["ir_digest"]]

        event = %{
          "kind" => "resume",
          "original" => previous["run"]["original"],
          "program_digest" => entry["program"]["ir_digest"]
        }

        %{
          entry
          | "event" => event,
            "prior" => %{"original" => previous["run"], "busy" => nil, "edge" => previous["edge"]}
        }
      end)
    end)
  end

  defp digest, do: "sha256:" <> String.duplicate("5", 64)
  defp due_event(c, "manual"), do: c.event

  defp due_event(c, "countdown"),
    do:
      signal(c, "elapsed_due", %{
        "schedule_id" => "countdown",
        "schedule_basis" => digest(),
        "due_elapsed_ms" => 50,
        "late_window_ms" => 500,
        "epoch" => c.time["epoch"],
        "clock_generation" => c.time["clock_generation"],
        "time_basis" => digest()
      })

  defp due_event(c, "due"),
    do:
      signal(c, "due", %{
        "schedule_id" => "due",
        "schedule_basis" => digest(),
        "due_ms" => c.time["utc_low_ms"],
        "late_window_ms" => 500,
        "clock_generation" => c.time["utc_generation"],
        "time_zone_basis" => digest()
      })

  defp choose(c, collection) do
    dispositions =
      Map.new(
        collection.data["proposals"],
        &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      )

    Arbitration.decide(collection, dispositions, 16, c.profile, c.limits)
  end
end
