defmodule Wotex.Routines.Test.ContinuationFixtures do
  @moduledoc false

  alias Wotex.Routines.{Compiler, Kernel, Limits, Profile}

  @spec fixture(keyword()) :: map()
  def fixture(options \\ []) do
    corpus = read("wro-01.json")
    continuation = read("wro-02-continuation.json")
    {:ok, limits} = Limits.new(Keyword.get(options, :limits, continuation["shapes"]["wide_limits"]))
    {:ok, profile} = Profile.new(continuation["profile"])
    actuator = Enum.at(corpus["bases"], 2)
    sensor = hd(corpus["bases"])
    bases = if options[:sensor], do: [actuator, sensor], else: [actuator]

    installed =
      Enum.map(bases, & &1["id"]) ++ ~w(interaction-security interaction-lifecycle qualified-report)

    bindings = %{
      "actuator" => %{
        "basis" => Map.take(actuator, ~w(id version semantic_digest)),
        "thing_id" => "urn:workcell:output",
        "resource_roles" => %{"target" => "resource:1"}
      }
    }

    bindings =
      if options[:sensor] do
        Map.put(bindings, "sensor", %{
          "basis" => Map.take(sensor, ~w(id version semantic_digest)),
          "thing_id" => corpus["fact"]["thing_id"],
          "resource_roles" => %{}
        })
      else
        bindings
      end

    context = %{
      "registry" => Enum.filter(corpus["registry"], &(&1["id"] in installed)),
      "bases" => bases,
      "bindings" => bindings,
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "procedure",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => Enum.sort(Map.keys(bindings)),
      "trigger" => %{"kind" => "manual"},
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => effect("apply"),
      "overlap" => "reject",
      "run_ms" => 1000
    }

    {:ok, date, _} = DateTime.from_iso8601(corpus["fact"]["source_time"])
    utc = DateTime.to_unix(date, :millisecond) + 500
    time = %{continuation["shapes"]["time1"] | "utc_low_ms" => utc, "utc_high_ms" => utc}

    %{
      corpus: corpus,
      vectors: continuation,
      profile: profile,
      limits: limits,
      context: context,
      source: source,
      time: time
    }
  end

  @spec compile(map(), map()) :: map()
  def compile(c, changes \\ %{}) do
    source = Map.merge(c.source, changes)
    {:ok, program} = Compiler.compile(source, c.context, c.profile, c.limits)

    revisions =
      c.context["bindings"]
      |> Map.values()
      |> Enum.flat_map(&[&1["thing_id"] | Map.values(&1["resource_roles"])])
      |> Map.new(&{&1, 1})

    bases =
      Map.new(c.context["bindings"], fn {name, binding} ->
        basis =
          if name == "sensor",
            do:
              Map.take(
                c.corpus["fact"],
                ~w(profile_digest source_id source_epoch source_time_basis)
              ),
            else: %{
              "profile_digest" => binding["basis"]["semantic_digest"],
              "source_id" => "device:1",
              "source_epoch" => "connection:1",
              "source_time_basis" => nil
            }

        {name, basis}
      end)

    snapshot = %{
      "id" => "snapshot:1",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => revisions,
      "binding_bases" => bases,
      "facts" => Map.new(Map.keys(c.context["bindings"]), &{&1, nil})
    }

    event = %{
      "kind" => "manual",
      "original" => "original:1",
      "program_digest" => program.data["ir_digest"]
    }

    Map.merge(c, %{source: source, program: program, snapshot: snapshot, event: event})
  end

  @spec effect(String.t(), boolean()) :: map()
  def effect(id, input \\ false),
    do: %{
      "id" => id,
      "kind" => "effect",
      "binding" => "actuator",
      "input" => input,
      "completion" => "reported_match"
    }

  @spec delayed_effect() :: map()
  def delayed_effect do
    %{
      "id" => "sequence",
      "kind" => "sequence",
      "steps" => [%{"id" => "pause", "kind" => "delay", "duration_ms" => 100}, effect("after")]
    }
  end

  @spec resume(map()) :: map()
  def resume(c),
    do: %{c | event: Map.put(Map.take(c.event, ~w(original program_digest)), "kind", "resume")}

  @spec advance(map(), map() | nil, map() | nil, map() | nil) ::
          {:ok, map()} | {:error, Wotex.Routines.Error.t()}
  def advance(c, run \\ nil, edge \\ nil, busy \\ nil),
    do:
      Kernel.advance(
        c.program,
        c.event,
        c.snapshot,
        c.time,
        %{"original" => run, "busy" => busy, "edge" => edge},
        c.profile,
        c.limits
      )

  @spec sample(map(), pos_integer(), non_neg_integer(), integer()) :: map()
  def sample(c, sequence, elapsed, value) do
    fact = %{
      c.corpus["fact"]
      | "id" => "sample:#{sequence}",
        "sequence" => sequence,
        "receipt_ms" => elapsed,
        "expires_ms" => elapsed + 1000,
        "value" => value
    }

    event = %{
      "kind" => "fact",
      "original" => "original:#{sequence}",
      "program_digest" => c.program.data["ir_digest"],
      "binding" => "sensor",
      "fact_id" => fact["id"]
    }

    %{
      c
      | event: event,
        time: %{c.time | "elapsed_ms" => elapsed},
        snapshot: put_in(c.snapshot, ["facts", "sensor"], fact)
    }
  end

  @spec collection(map(), pos_integer()) :: map()
  def collection(c, count) do
    members =
      Enum.map(1..count, fn index ->
        compile(c, %{"id" => "procedure:#{index}", "steps" => effect("apply", rem(index, 2) == 0)})
      end)

    programs = Enum.map(members, & &1.program.data["ir_digest"])

    entries =
      Enum.map(members, fn member ->
        %{
          "program" => member.program.data,
          "event" => member.event,
          "snapshot" => %{member.snapshot | "active_programs" => programs},
          "prior" => %{"original" => nil, "busy" => nil, "edge" => nil}
        }
      end)

    %{
      "membership" => %{"generation" => "membership:1", "programs" => programs},
      "entries" => entries,
      "time" => c.time
    }
  end

  defp read(name) do
    :wotex_routines
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("vectors/" <> name)
    |> File.read!()
    |> JSON.decode!()
  end
end
