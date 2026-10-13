defmodule PrivateCompositionJournal do
  @moduledoc false

  @terminal ~w(completed refused failed unknown cancelled expired partial)

  @spec start_link(map(), map()) :: {:ok, pid()}
  def start_link(snapshot, time),
    do:
      Agent.start_link(fn ->
        %{
          revision: 0,
          run: nil,
          edge: nil,
          snapshot: snapshot,
          time: time,
          policy: :allow,
          outcomes: []
        }
      end)

  @spec read(pid()) :: map()
  def read(owner), do: Agent.get(owner, & &1)

  @spec replace(pid(), map()) :: :ok
  def replace(owner, changes),
    do:
      Agent.update(owner, fn state ->
        state
        |> Map.merge(changes)
        |> Map.put(:revision, state.revision + 1)
      end)

  @spec prior(map()) :: map()
  def prior(state),
    do: %{
      "original" => state.run,
      "edge" => state.edge,
      "busy" => if(state.run && state.run["status"] not in @terminal, do: state.run, else: nil)
    }

  @spec commit(pid(), non_neg_integer(), map()) :: :ok | {:error, atom()}
  def commit(owner, revision, transition),
    do:
      Agent.get_and_update(owner, fn state ->
        basis = transition["basis"]

        cond do
          state.revision != revision or basis["prior"] != prior(state) or
            basis["snapshot"] != state.snapshot or basis["time"] != state.time ->
            {{:error, :stale}, state}

          state.policy != :allow ->
            {{:error, :policy_refused}, state}

          true ->
            {:ok,
             %{
               state
               | revision: state.revision + 1,
                 run: transition["run"],
                 edge: transition["edge"],
                 outcomes: [transition["outcome"] | state.outcomes]
             }}
        end
      end)
end

defmodule PrivateJournalArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Arbitration, Collection, Compiler, Kernel, Limits, Profile}

  setup do
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

    basis = Enum.at(corpus["bases"], 2)

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "procedure",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => ["output"],
      "trigger" => %{"kind" => "manual"},
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => %{
        "id" => "sequence",
        "kind" => "sequence",
        "steps" => [effect("first"), effect("second")]
      },
      "overlap" => "reject",
      "run_ms" => 1000
    }

    context = %{
      "registry" => corpus["registry"],
      "bases" => corpus["bases"],
      "bindings" => %{
        "output" => %{
          "basis" => Map.take(basis, ~w(id version semantic_digest)),
          "thing_id" => "urn:cell:output",
          "resource_roles" => %{"target" => "cell:1"}
        }
      },
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => System.fetch_env!("WOTEX_ROUTINES_COMPILER_BASIS")
    }

    {:ok, program} = Compiler.compile(source, context, profile, limits)

    snapshot = %{
      "id" => "snapshot:1",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{"urn:cell:output" => 1, "cell:1" => 1},
      "binding_bases" => %{
        "output" => %{
          "profile_digest" => basis["semantic_digest"],
          "source_id" => "output:1",
          "source_epoch" => "connection:1",
          "source_time_basis" => nil
        }
      },
      "facts" => %{"output" => nil}
    }

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => 20,
      "clock_generation" => "clock:1",
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    {:ok, owner} = PrivateCompositionJournal.start_link(snapshot, time)
    on_exit(fn -> if Process.alive?(owner), do: Agent.stop(owner) end)

    %{
      limits: limits,
      profile: profile,
      basis: basis,
      program: program,
      snapshot: snapshot,
      time: time,
      owner: owner,
      source: source,
      context: context
    }
  end

  test "consumer-owned commit retains every stage and advances only on reported match", c do
    assert [[0]] == paths(commit(c, "manual"))
    assert [] == paths(commit(c, "admission"))
    assert [] == paths(commit(c, "handoff"))
    assert [] == paths(commit(c, "result", "protocol_response"))
    assert [[1]] == paths(commit(c, "result", "reported_match"))
    state = PrivateCompositionJournal.read(c.owner)
    assert length(state.run["spent"]) == 1
    assert hd(state.run["steps"])["path"] == []

    assert state.run["steps"]
           |> Enum.find(&(&1["path"] == [0]))
           |> Map.fetch!("status") ==
             "completed"
  end

  test "a newer held receipt cannot be overwritten by an older prepared transition", c do
    commit(c, "manual")
    {revision, old} = prepare(c, "manual")
    held = commit(c, "admission")
    assert {:error, :stale} == PrivateCompositionJournal.commit(c.owner, revision, old)
    assert PrivateCompositionJournal.read(c.owner).run == held["run"]
    assert length(held["run"]["spent"]) == 1
  end

  test "consumer policy and snapshot changes refuse stale work without issuing a handoff", c do
    for changes <- [
          %{policy: :deny},
          %{snapshot: %{c.snapshot | "id" => "snapshot:2"}},
          %{time: %{c.time | "clock_generation" => "clock:2"}}
        ] do
      {revision, transition} = prepare(c, "manual")
      PrivateCompositionJournal.replace(c.owner, changes)
      assert {:error, :stale} == PrivateCompositionJournal.commit(c.owner, revision, transition)
      assert PrivateCompositionJournal.read(c.owner).run == nil

      PrivateCompositionJournal.replace(c.owner, %{
        policy: :allow,
        snapshot: c.snapshot,
        time: c.time
      })
    end

    PrivateCompositionJournal.replace(c.owner, %{policy: :deny})
    {revision, transition} = prepare(c, "manual")

    assert {:error, :policy_refused} ==
             PrivateCompositionJournal.commit(c.owner, revision, transition)

    assert PrivateCompositionJournal.read(c.owner).outcomes == []
  end

  test "cancelled handoff accepts later evidence without proposing the dependent step", c do
    commit(c, "manual")
    commit(c, "admission")
    commit(c, "handoff")
    cancelled = commit(c, "cancel")
    later = commit(c, "result", "reported_match")
    assert cancelled["outcome"] == "cancelled"
    assert later["outcome"] == "cancelled"
    assert later["proposals"] == []
    assert later["run"]["spent"] == cancelled["run"]["spent"]
  end

  test "an incompatible proposal beyond a one-group cutoff still prevents both selections", c do
    other_source = %{
      c.source
      | "id" => "other",
        "steps" => %{effect("other-effect") | "input" => true}
    }

    {:ok, other} = Compiler.compile(other_source, c.context, c.profile, c.limits)
    programs = [c.program.data, other.data]
    digests = Enum.map(programs, & &1["ir_digest"])
    snapshot = %{c.snapshot | "active_programs" => digests}

    entries =
      Enum.map(programs, fn program ->
        %{
          "program" => program,
          "event" => %{
            "kind" => "manual",
            "original" => "original:" <> program["source"]["id"],
            "program_digest" => program["ir_digest"]
          },
          "snapshot" => snapshot,
          "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
        }
      end)

    input = %{
      "membership" => %{"generation" => "membership:1", "programs" => digests},
      "entries" => entries,
      "time" => c.time
    }

    assert {:ok, collection} = Collection.evaluate(input, c.profile, c.limits)

    dispositions =
      Map.new(collection.data["proposals"], fn proposal ->
        {proposal["step_original"], %{"constraint" => "allowed", "override" => "none"}}
      end)

    assert {:ok, result} = Arbitration.decide(collection, dispositions, 1, c.profile, c.limits)
    assert result["selected"] == []
    assert Enum.map(result["decisions"], & &1["outcome"]) == ["conflict", "conflict"]
  end

  defp prepare(c, kind, stage \\ nil) do
    state = PrivateCompositionJournal.read(c.owner)
    event = event(c, kind, stage)

    assert {:ok, transition} =
             Kernel.advance(
               c.program,
               event,
               state.snapshot,
               state.time,
               PrivateCompositionJournal.prior(state),
               c.profile,
               c.limits
             )

    {state.revision, transition}
  end

  defp commit(c, kind, stage \\ nil) do
    {revision, transition} = prepare(c, kind, stage)
    assert :ok == PrivateCompositionJournal.commit(c.owner, revision, transition)
    transition
  end

  defp event(c, kind, stage) do
    event = %{
      "kind" => kind,
      "original" => "original:1",
      "program_digest" => c.program.data["ir_digest"]
    }

    case kind do
      "admission" ->
        Map.merge(event, %{"path" => [0], "ref" => "held:1", "outcome" => "held"})

      "handoff" ->
        Map.merge(event, %{"path" => [0], "ref" => "handoff:1"})

      "result" ->
        Map.merge(event, %{
          "path" => [0],
          "ref" => "result:" <> stage,
          "stage" => stage,
          "outcome" => "accepted",
          "report_contract" =>
            if(stage in ~w(correlated_report reported_match),
              do: c.basis["evidence"]["report_contract"],
              else: nil
            )
        })

      _ ->
        event
    end
  end

  defp effect(id),
    do: %{
      "id" => id,
      "kind" => "effect",
      "binding" => "output",
      "input" => false,
      "completion" => "reported_match"
    }

  defp paths(transition), do: Enum.map(transition["proposals"], & &1["path"])
end
