defmodule Wotex.Routines.Test.CivilFixtures do
  @moduledoc false

  alias Wotex.Routines.{Compiler, Limits, Profile, Schedule}

  @spec load() :: map()
  def load do
    priv =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()

    corpus =
      priv
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    vector =
      priv
      |> Path.join("vectors/wro-03-civil.json")
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

    schema =
      priv
      |> Path.join("schemas/wro-03-temporal.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    %{
      corpus: corpus,
      vector: vector,
      limits: limits,
      profile: profile,
      schema: schema,
      time: vector["time"],
      query: vector["query"],
      schedule: vector["schedule"]
    }
  end

  @spec schedule(map(), map()) :: map()
  def schedule(c, changes \\ %{}) do
    raw = Map.merge(c.schedule, changes)
    {:ok, digest} = Schedule.semantic_digest(raw, c.limits)
    %{raw | "definition_digest" => digest}
  end

  @spec program(map(), map()) :: Wotex.Routines.Program.t()
  def program(c, schedule) do
    source = %{
      "format" => "wotex.routines.source@1",
      "profile" => "bounded-composition@1",
      "id" => "civil",
      "revision" => "1",
      "parameters" => %{},
      "bindings" => [],
      "trigger" => %{
        "kind" => "due",
        "schedule_id" => schedule["schedule_id"],
        "schedule_basis" => schedule["definition_digest"]
      },
      "condition" => %{"op" => "literal", "value" => true},
      "steps" => %{"id" => "done", "kind" => "noop"},
      "overlap" => "reject",
      "run_ms" => 1000
    }

    context = %{
      "registry" => c.corpus["registry"],
      "bases" => c.corpus["bases"],
      "bindings" => %{},
      "definitions" => [],
      "arguments" => %{},
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    {:ok, program} = Compiler.compile(source, context, c.profile, c.limits)
    program
  end
end
