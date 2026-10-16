defmodule ContinuationSourceOracle do
  @moduledoc false

  @spec pending(map(), non_neg_integer(), non_neg_integer(), MapSet.t()) :: [list()]
  def pending(source, started, elapsed, completed \\ MapSet.new()) do
    {_, paths, _} = walk(source["steps"], [], started, elapsed, completed)
    paths
  end

  @spec window_open?(map(), map(), map()) :: boolean()
  def window_open?(%{"kind" => "manual"}, _, _), do: true

  def window_open?(%{"kind" => "countdown"}, original, now) do
    original["epoch"] == now["epoch"] and
      original["clock_generation"] == now["clock_generation"] and
      now["elapsed_ms"] >= original["elapsed_ms"] and
      now["elapsed_ms"] < original["elapsed_ms"] + 500
  end

  def window_open?(%{"kind" => "due"}, original, now) do
    original["utc_generation"] == now["utc_generation"] and
      is_integer(now["utc_low_ms"]) and is_integer(now["utc_high_ms"]) and
      now["utc_low_ms"] >= original["utc_low_ms"] and
      now["utc_high_ms"] < original["utc_low_ms"] + 500
  end

  defp walk(%{"kind" => "effect"}, path, started, _, completed) do
    path = Enum.reverse(path)
    if MapSet.member?(completed, path), do: {true, [], started}, else: {false, [path], started}
  end

  defp walk(%{"kind" => "delay", "duration_ms" => duration}, _, started, elapsed, _) do
    ready = started + duration
    {elapsed >= ready, [], ready}
  end

  defp walk(%{"kind" => "sequence", "steps" => children}, path, started, elapsed, completed) do
    children
    |> Enum.with_index()
    |> Enum.reduce_while({true, [], started}, fn {child, index}, {_, _, coordinate} ->
      result = walk(child, [index | path], coordinate, elapsed, completed)
      if elem(result, 0), do: {:cont, result}, else: {:halt, result}
    end)
  end
end

defmodule ContinuationSourceConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true

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
        "max_bytes" => 67_108_864,
        "max_depth" => 64,
        "max_nodes" => 2_000_000,
        "max_collection_size" => 8192,
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
        "pending_work" => 1024,
        "run_ms" => 86_400_000
      })

    {:ok, date, _} = DateTime.from_iso8601(corpus["fact"]["source_time"])
    utc = DateTime.to_unix(date, :millisecond) + 500

    time = %{
      "format" => "wotex.routines.time@2",
      "epoch" => "source:boot",
      "elapsed_ms" => 20,
      "clock_generation" => "elapsed:stable",
      "utc_generation" => "utc:one",
      "utc_low_ms" => utc,
      "utc_high_ms" => utc
    }

    %{corpus: corpus, limits: limits, profile: profile, time: time}
  end

  test "source delay resumes the same edge original without consuming another sample", base do
    trigger = %{
      "kind" => "edge",
      "binding" => "measurement",
      "direction" => "rising",
      "debounce_ms" => 0,
      "cooldown_ms" => 200,
      "hysteresis" => %{"enter" => 2500, "exit" => 1500}
    }

    c = compile(base, "edge", trigger: trigger, delayed: true)
    baseline = sample(c, 1, 20, 1000)
    assert {:ok, first} = advance(baseline, nil)
    assert first["outcome"] == "no-edge"
    rising = sample(c, 2, 30, 3000)
    assert {:ok, started} = advance(rising, nil, first["edge"])
    assert started["outcome"] == "running"
    assert paths(started["proposals"]) == ContinuationSourceOracle.pending(c.source, 30, 30)
    resumed = sample(c, 3, 130, 1000)

    resumed = %{
      resumed
      | event: event(c, "resume", %{"original" => rising.event["original"]}),
        time: %{resumed.time | "utc_generation" => "utc:two"}
    }

    assert {:ok, result} = advance(resumed, started["run"], started["edge"])
    assert paths(result["proposals"]) == ContinuationSourceOracle.pending(c.source, 30, 130)
    assert paths(result["proposals"]) == [[1]]
    assert result["edge"] == started["edge"]
    assert result["run"]["original"] == rising.event["original"]

    assert Enum.map(result["run"]["steps"], & &1["original"]) ==
             Enum.map(started["run"]["steps"], & &1["original"])
  end

  test "source windows distinguish manual and elapsed work from a corrected UTC basis", base do
    members =
      Enum.map(~w(manual countdown due), fn kind ->
        trigger =
          if kind == "manual",
            do: %{"kind" => kind},
            else: %{"kind" => kind, "schedule_id" => kind, "schedule_basis" => digest()}

        c = compile(base, kind, trigger: trigger, delayed: true)
        %{c | event: scheduled(c, kind)}
      end)

    input = collection_input(base, members)
    assert {:ok, initial} = Collection.evaluate(input, base.profile, base.limits)
    now = %{base.time | "elapsed_ms" => 120, "utc_generation" => "utc:two"}
    next = %{retained(initial) | "time" => now}
    assert {:ok, current} = Collection.evaluate(next, base.profile, base.limits)
    by_digest = Map.new(members, &{&1.program.data["ir_digest"], &1})

    for row <- current.data["transitions"] do
      c = by_digest[row["program_digest"]]
      live = ContinuationSourceOracle.window_open?(c.source["trigger"], base.time, now)
      expected = if live, do: ContinuationSourceOracle.pending(c.source, 20, 120), else: []
      assert paths(row["result"]["proposals"]) == expected
      assert row["result"]["outcome"] == if(live, do: "running", else: "expired")
      assert row["result"]["basis"]["time"] == now
    end

    assert length(current.data["proposals"]) == 2
    assert {:ok, repeated} = Collection.evaluate(retained(current), base.profile, base.limits)
    assert repeated.data["proposals"] == current.data["proposals"]
    assert Enum.all?(repeated.data["transitions"], &(&1["result"]["proposals"] == []))
  end

  test "a source property match completes without fabricated stages or refunded admission", base do
    for reserved <- [false, true] do
      c = compile(base, "matching")
      assert {:ok, proposed} = advance(c, nil)

      admitted =
        if reserved do
          assert {:ok, held} =
                   advance(
                     %{
                       c
                       | event:
                           event(c, "admission", %{
                             "path" => [],
                             "ref" => "charge:original",
                             "outcome" => "held"
                           })
                     },
                     proposed["run"]
                   )

          held
        else
          proposed
        end

      matching = matching_fact(c)

      satisfied =
        event(c, "satisfied", %{
          "path" => [],
          "ref" => "match:original",
          "fact_id" => "reported:current",
          "report_contract" => Enum.at(c.corpus["bases"], 2)["evidence"]["report_contract"]
        })

      matching = %{matching | event: satisfied}
      assert {:ok, completed} = advance(matching, admitted["run"])
      assert completed["outcome"] == "completed"
      assert completed["run"]["spent"] == admitted["run"]["spent"]
      assert length(completed["run"]["spent"]) == if(reserved, do: 1, else: 0)
      [record] = completed["run"]["steps"]
      assert record["receipts"]["satisfied"]["outcome"] == "matched"

      assert Enum.all?(
               ~w(handoff local_queue protocol_response correlated_report reported_match terminal),
               &(record["receipts"][&1] == nil)
             )

      assert paths(completed["proposals"]) ==
               ContinuationSourceOracle.pending(c.source, 20, 20, MapSet.new([[]]))

      absent = %{
        matching
        | snapshot: put_in(matching.snapshot, ["facts", "output"], nil),
          time: %{c.time | "elapsed_ms" => 2000}
      }

      assert {:ok, repeated} = advance(absent, completed["run"])
      assert repeated["run"] == completed["run"]
      assert repeated["proposals"] == []
    end
  end

  test "independent source paths remain in a complete pending cut above the batch limit", base do
    members = Enum.map(1..3, &compile(base, "member:#{&1}", target: "target:#{&1}"))
    input = collection_input(base, members)
    assert {:ok, initial} = Collection.evaluate(input, base.profile, base.limits)
    [entry | rest] = retained(initial)["entries"]

    admission =
      Map.merge(entry["event"], %{
        "kind" => "admission",
        "path" => [],
        "ref" => "charge:member",
        "outcome" => "held"
      })

    next = %{retained(initial) | "entries" => [%{entry | "event" => admission} | rest]}
    assert {:ok, current} = Collection.evaluate(next, base.profile, base.limits)

    expected =
      Enum.flat_map(members, fn c ->
        Enum.map(
          ContinuationSourceOracle.pending(c.source, 20, 20),
          &{c.program.data["ir_digest"], &1}
        )
      end)
      |> Enum.sort()

    assert Enum.sort(Enum.map(current.data["proposals"], &{&1["program_digest"], &1["path"]})) ==
             expected

    assert current.data["proposals"] == initial.data["proposals"]
    assert Enum.count(current.data["proposal_states"], &(&1["status"] == "reserved")) == 1

    ds =
      Map.new(
        current.data["proposals"],
        &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      )

    assert {:ok, decision} = Arbitration.decide(current, ds, 1, base.profile, base.limits)
    assert length(decision["selected"]) == 1
    assert Enum.count(decision["decisions"], &(&1["outcome"] == "batch-deferred")) == 2
    c = hd(members)

    assert {:error, %Error{code: :missing_original}} =
             advance(%{c | event: event(c, "resume")}, nil)

    assert {:error, %Error{code: :incomplete_run_continuation}} =
             Collection.evaluate(
               put_in(next, ["entries", Access.at(0), "event"], nil),
               base.profile,
               base.limits
             )
  end

  defp compile(base, id, opts \\ []) do
    actuator = Enum.at(base.corpus["bases"], 2)
    sensor = hd(base.corpus["bases"])
    target = Keyword.get(opts, :target, "target:shared")

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => id,
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ~w(measurement output),
      "trigger" => Keyword.get(opts, :trigger, %{"kind" => "manual"}),
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => effect(),
      "overlap" => "reject",
      "run_ms" => 1000
    }

    source =
      if opts[:delayed],
        do: %{
          source
          | "steps" => %{
              "id" => "sequence",
              "kind" => "sequence",
              "steps" => [%{"id" => "delay", "kind" => "delay", "duration_ms" => 100}, effect()]
            }
        },
        else: source

    context = %{
      "registry" => base.corpus["registry"],
      "bases" => base.corpus["bases"],
      "bindings" => %{
        "output" => %{
          "basis" => Map.take(actuator, ~w(id version semantic_digest)),
          "thing_id" => "urn:source:" <> target,
          "resource_roles" => %{"target" => target}
        },
        "measurement" => %{
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
      "id" => "source:cut",
      "membership_generation" => "source:members",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{
        ("urn:source:" <> target) => 1,
        target => 1,
        base.corpus["fact"]["thing_id"] => 1
      },
      "binding_bases" => %{
        "output" => %{
          "profile_digest" => actuator["semantic_digest"],
          "source_id" => "output:1",
          "source_epoch" => "connection:1",
          "source_time_basis" => base.corpus["fact"]["source_time_basis"]
        },
        "measurement" =>
          Map.take(base.corpus["fact"], ~w(profile_digest source_id source_epoch source_time_basis))
      },
      "facts" => %{"output" => nil, "measurement" => nil}
    }

    c = Map.merge(base, %{program: program, source: source, snapshot: snapshot})
    Map.put(c, :event, event(c, "manual"))
  end

  defp effect,
    do: %{
      "id" => "apply",
      "kind" => "effect",
      "binding" => "output",
      "input" => false,
      "completion" => "reported_match"
    }

  defp digest, do: "sha256:" <> String.duplicate("6", 64)

  defp event(c, kind, extra \\ %{}),
    do:
      Map.merge(
        %{
          "kind" => kind,
          "original" => "original:" <> c.source["id"],
          "program_digest" => c.program.data["ir_digest"]
        },
        extra
      )

  defp paths(proposals), do: Enum.map(proposals, & &1["path"])

  defp advance(c, run, edge \\ nil),
    do:
      Kernel.advance(
        c.program,
        c.event,
        c.snapshot,
        c.time,
        %{"original" => run, "busy" => nil, "edge" => edge},
        c.profile,
        c.limits
      )

  defp sample(c, sequence, elapsed, value) do
    fact =
      Map.merge(c.corpus["fact"], %{
        "id" => "sample:#{sequence}",
        "sequence" => sequence,
        "receipt_epoch" => c.time["epoch"],
        "receipt_ms" => elapsed,
        "expires_ms" => elapsed + 1000,
        "value" => value
      })

    %{
      c
      | snapshot: put_in(c.snapshot, ["facts", "measurement"], fact),
        time: %{c.time | "elapsed_ms" => elapsed},
        event:
          event(c, "fact", %{
            "original" => "edge:#{sequence}",
            "binding" => "measurement",
            "fact_id" => fact["id"]
          })
    }
  end

  defp matching_fact(c) do
    basis = Enum.at(c.corpus["bases"], 2)

    fact =
      Map.merge(c.corpus["fact"], %{
        "id" => "reported:current",
        "thing_id" => c.program.data["context"]["bindings"]["output"]["thing_id"],
        "affordance_name" => "fast",
        "value" => false,
        "unit" => nil,
        "source_id" => "output:1",
        "profile_digest" => basis["semantic_digest"],
        "receipt_epoch" => c.time["epoch"]
      })

    %{c | snapshot: put_in(c.snapshot, ["facts", "output"], fact)}
  end

  defp scheduled(c, "manual"), do: c.event

  defp scheduled(c, "countdown"),
    do:
      event(c, "elapsed_due", %{
        "schedule_id" => "countdown",
        "schedule_basis" => digest(),
        "due_elapsed_ms" => 20,
        "late_window_ms" => 500,
        "epoch" => c.time["epoch"],
        "clock_generation" => c.time["clock_generation"],
        "time_basis" => digest()
      })

  defp scheduled(c, "due"),
    do:
      event(c, "due", %{
        "schedule_id" => "due",
        "schedule_basis" => digest(),
        "due_ms" => c.time["utc_low_ms"],
        "late_window_ms" => 500,
        "clock_generation" => c.time["utc_generation"],
        "time_zone_basis" => digest()
      })

  defp collection_input(base, members) do
    programs = Enum.map(members, & &1.program.data["ir_digest"])

    %{
      "format" => "wotex.routines.collection-input@2",
      "membership" => %{"generation" => "source:members", "programs" => programs},
      "entries" =>
        Enum.map(
          members,
          &%{
            "program" => &1.program.data,
            "event" => &1.event,
            "snapshot" => %{&1.snapshot | "active_programs" => programs},
            "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
          }
        ),
      "time" => base.time
    }
  end

  defp retained(collection) do
    runs = Map.new(collection.data["transitions"], &{&1["program_digest"], &1["result"]["run"]})

    update_in(collection.data["input"], ["entries"], fn entries ->
      Enum.map(entries, fn entry ->
        run = runs[entry["program"]["ir_digest"]]

        %{
          entry
          | "event" => %{
              "kind" => "resume",
              "original" => run["original"],
              "program_digest" => run["program_digest"]
            },
            "prior" => %{entry["prior"] | "original" => run}
        }
      end)
    end)
  end
end
