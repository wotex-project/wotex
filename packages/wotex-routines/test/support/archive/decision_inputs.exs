defmodule DecisionArchiveInputs do
  @moduledoc false

  # Shared synthetic declarations and claim preparation only. Expected motion,
  # cells, charge history and arbitration belong to the separate consumer oracles.
  alias Wotex.Routines.{Arbitration, Basis, Collection, Compiler, Decision, Kernel, Limits, Profile}

  @spec base() :: map()
  def base do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> to_string()
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
      "epoch" => "archive:boot",
      "elapsed_ms" => 20,
      "clock_generation" => "elapsed:one",
      "utc_generation" => "utc:one",
      "utc_low_ms" => utc,
      "utc_high_ms" => utc
    }

    %{corpus: corpus, profile: profile, limits: limits, time: time}
  end

  @spec compile(map(), String.t(), keyword()) :: map()
  def compile(base, id, opts \\ []) do
    bases =
      Enum.map(base.corpus["bases"], fn basis ->
        basis =
          put_in(basis, ["evidence", "require_source_time"], Keyword.get(opts, :source_time, false))

        {:ok, digest} = Basis.semantic_digest(basis, base.limits)
        %{basis | "semantic_digest" => digest}
      end)

    digests = Map.new(bases, &{&1["id"], &1["semantic_digest"]})

    registry =
      Enum.map(base.corpus["registry"], fn ref ->
        if Map.has_key?(digests, ref["id"]),
          do: %{ref | "semantic_digest" => digests[ref["id"]]},
          else: ref
      end)

    actuator = Enum.at(bases, 2)
    sensor = hd(bases)
    target = Keyword.get(opts, :target, "shared")

    output = %{
      "basis" => Map.take(actuator, ~w(id version semantic_digest)),
      "thing_id" => "urn:archive:" <> target,
      "resource_roles" => %{"target" => "resource:" <> target}
    }

    bindings = %{"output" => output}

    bindings =
      if opts[:sensor],
        do:
          Map.put(bindings, "measurement", %{
            "basis" => Map.take(sensor, ~w(id version semantic_digest)),
            "thing_id" => base.corpus["fact"]["thing_id"],
            "resource_roles" => %{}
          }),
        else: bindings

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => id,
      "revision" => "1",
      "parameters" => %{},
      "bindings" => Enum.sort(Map.keys(bindings)),
      "trigger" => Keyword.get(opts, :trigger, %{"kind" => "manual"}),
      "condition" => Keyword.get(opts, :condition, literal(true)),
      "steps" => Keyword.get(opts, :steps, effect()),
      "overlap" => "reject",
      "run_ms" => Keyword.get(opts, :run_ms, 1000)
    }

    context = %{
      "registry" => registry,
      "bases" => bases,
      "bindings" => bindings,
      "definitions" => Keyword.get(opts, :definitions, []),
      "arguments" => %{},
      "compiler_basis" => System.fetch_env!("WOTEX_ROUTINES_COMPILER_BASIS")
    }

    {:ok, program} = Compiler.compile(source, context, base.profile, base.limits)

    revisions =
      bindings
      |> Map.values()
      |> Enum.flat_map(&[&1["thing_id"] | Map.values(&1["resource_roles"])])
      |> Map.new(&{&1, 1})

    expected =
      Map.new(bindings, fn {name, binding} ->
        value =
          if name == "measurement",
            do:
              base.corpus["fact"]
              |> Map.take(~w(profile_digest source_id source_epoch source_time_basis))
              |> Map.put("profile_digest", sensor["semantic_digest"]),
            else: %{
              "profile_digest" => binding["basis"]["semantic_digest"],
              "source_id" => "output:one",
              "source_epoch" => "connection:one",
              "source_time_basis" => base.corpus["fact"]["source_time_basis"]
            }

        {name, value}
      end)

    snapshot = %{
      "id" => "archive:cut",
      "membership_generation" => "archive:members",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => revisions,
      "binding_bases" => expected,
      "facts" => Map.new(Map.keys(bindings), &{&1, nil})
    }

    c = Map.merge(base, %{program: program, source: source, context: context, snapshot: snapshot})
    Map.put(c, :event, event(c, "manual"))
  end

  @spec literal(boolean() | String.t()) :: map()
  def literal(value), do: %{"op" => "literal", "value" => value}

  @spec effect(String.t(), boolean()) :: map()
  def effect(id \\ "apply", input \\ false),
    do: %{
      "id" => id,
      "kind" => "effect",
      "binding" => "output",
      "input" => input,
      "completion" => "reported_match"
    }

  @spec delay(non_neg_integer(), boolean()) :: map()
  def delay(duration, input \\ false),
    do: %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [
        %{"id" => "pause", "kind" => "delay", "duration_ms" => duration},
        effect("after", input)
      ]
    }

  @spec event(map(), String.t(), map()) :: map()
  def event(c, kind, extra \\ %{}),
    do:
      Map.merge(
        %{
          "kind" => kind,
          "original" => "original:" <> c.source["id"],
          "program_digest" => c.program.data["ir_digest"]
        },
        extra
      )

  @spec prior(map() | nil, map() | nil) :: map()
  def prior(run \\ nil, edge \\ nil), do: %{"original" => run, "busy" => nil, "edge" => edge}

  @spec point(map(), map() | nil, map() | nil) :: map()
  def point(c, run \\ nil, edge \\ nil) do
    {:ok, result} =
      Kernel.advance(c.program, c.event, c.snapshot, c.time, prior(run, edge), c.profile, c.limits)

    result
  end

  @spec input(map(), [map()]) :: map()
  def input(base, members) do
    ids = Enum.map(members, & &1.program.data["ir_digest"])

    entries =
      Enum.map(
        members,
        &%{
          "program" => &1.program.data,
          "event" => &1.event,
          "snapshot" => %{&1.snapshot | "active_programs" => ids},
          "prior" => prior()
        }
      )

    %{
      "format" => "wotex.routines.collection-input@2",
      "membership" => %{"generation" => "archive:members", "programs" => ids},
      "entries" => entries,
      "time" => base.time
    }
  end

  @spec collection(map(), map()) :: Collection.t()
  def collection(base, input) do
    {:ok, result} = Collection.evaluate(input, base.profile, base.limits)
    result
  end

  @spec claimed(map(), map()) :: Collection.t()
  def claimed(base, input) do
    transitions =
      input["entries"]
      |> Enum.sort_by(& &1["program"]["ir_digest"])
      |> Enum.map(fn entry ->
        {:ok, result} =
          Kernel.advance(
            entry["program"],
            entry["event"],
            entry["snapshot"],
            input["time"],
            entry["prior"],
            base.profile,
            base.limits
          )

        %{"program_digest" => entry["program"]["ir_digest"], "result" => result}
      end)

    proposals = Enum.flat_map(transitions, & &1["result"]["proposals"])

    data = %{
      "format" => "wotex.routines.collection@2",
      "input" => input,
      "profile" => base.profile.data,
      "json_limits" => base.limits.data,
      "transitions" => transitions,
      "proposals" => proposals,
      "proposal_states" =>
        Enum.map(proposals, &%{"step_original" => &1["step_original"], "status" => "proposed"})
    }

    %Collection{data: rehash(data, "collection_digest")}
  end

  @spec retained(Collection.t()) :: map()
  def retained(collection) do
    results = Map.new(collection.data["transitions"], &{&1["program_digest"], &1["result"]})

    update_in(collection.data["input"], ["entries"], fn entries ->
      Enum.map(entries, fn entry ->
        result = results[entry["program"]["ir_digest"]]
        run = result["run"]

        %{
          entry
          | "event" => %{
              "kind" => "resume",
              "program_digest" => run["program_digest"],
              "original" => run["original"]
            },
            "prior" => prior(run, result["edge"])
        }
      end)
    end)
  end

  @spec decision(map(), Collection.t()) :: Decision.t()
  def decision(base, collection) do
    {:ok, decision} = Decision.new(collection, base.profile, base.limits)
    decision
  end

  @spec current(map(), Collection.t(), pos_integer(), map() | nil) :: map()
  def current(base, collection, batch \\ 1, dispositions \\ nil) do
    ds =
      dispositions ||
        Map.new(
          collection.data["proposals"],
          &{&1["step_original"], %{"constraint" => "allowed", "override" => "none"}}
        )

    {:ok, arbitration} = Arbitration.decide(collection, ds, batch, base.profile, base.limits)

    %{
      "input" => collection.data["input"],
      "dispositions" => ds,
      "batch_limit" => batch,
      "arbitration" => arbitration
    }
  end

  @spec sample(map(), pos_integer(), integer(), non_neg_integer()) :: map()
  def sample(c, sequence, value, elapsed) do
    fact =
      Map.merge(c.corpus["fact"], %{
        "id" => "sample:#{sequence}",
        "sequence" => sequence,
        "profile_digest" => c.snapshot["binding_bases"]["measurement"]["profile_digest"],
        "receipt_epoch" => c.time["epoch"],
        "receipt_ms" => elapsed,
        "expires_ms" => elapsed + 1000,
        "value" => value
      })

    %{
      c
      | event:
          event(c, "fact", %{
            "binding" => "measurement",
            "fact_id" => fact["id"],
            "original" => "edge:#{sequence}"
          }),
        snapshot: put_in(c.snapshot, ["facts", "measurement"], fact),
        time: %{c.time | "elapsed_ms" => elapsed}
    }
  end

  @spec matching(map()) :: map()
  def matching(c) do
    basis = c.snapshot["binding_bases"]["output"]
    binding = c.context["bindings"]["output"]
    actuator = Enum.at(c.context["bases"], 2)

    fact =
      Map.merge(c.corpus["fact"], %{
        "id" => "output:current",
        "value" => false,
        "unit" => nil,
        "thing_id" => binding["thing_id"],
        "affordance_name" => actuator["affordance"]["name"],
        "profile_digest" => basis["profile_digest"],
        "source_id" => basis["source_id"],
        "source_epoch" => basis["source_epoch"],
        "receipt_epoch" => c.time["epoch"],
        "receipt_ms" => c.time["elapsed_ms"],
        "expires_ms" => c.time["elapsed_ms"] + 1000
      })

    %{c | snapshot: put_in(c.snapshot, ["facts", "output"], fact)}
  end

  @spec hash(term()) :: String.t()
  def hash(data) do
    {:ok, bytes} =
      Wotex.JSON.encode(data,
        max_bytes: 67_108_864,
        max_depth: 64,
        max_nodes: 2_000_000,
        max_collection_size: 8192,
        max_string_bytes: 65_536
      )

    "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  end

  @spec rehash(map(), String.t()) :: map()
  def rehash(data, member), do: Map.put(data, member, hash(Map.delete(data, member)))
end
