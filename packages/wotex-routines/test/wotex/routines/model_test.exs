defmodule Wotex.Routines.ModelTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Compiler, Error, Kernel, Limits, Model, Profile}

  setup_all do
    root =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()

    corpus =
      root
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    scope =
      root
      |> Path.join("vectors/wro-04-proposal-prefix.json")
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("scope")

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
        "id" => "apply",
        "kind" => "effect",
        "binding" => "output",
        "input" => false,
        "completion" => "reported_match"
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
      "compiler_basis" => "sha256:" <> String.duplicate("7", 64)
    }

    %{
      root: root,
      corpus: corpus,
      scope: scope,
      limits: limits,
      profile: profile,
      source: source,
      context: context,
      basis: basis
    }
  end

  test "both exact Boolean proposal prefixes agree with the source and public kernel", c do
    for value <- [false, true] do
      source = put_in(c.source, ["steps", "input"], value)
      {:ok, program} = Compiler.compile(source, c.context, c.profile, c.limits)
      assert {:ok, model} = Model.compile(program, c.scope, c.profile, c.limits)
      assert {:ok, data} = Model.to_map(model, c.profile, c.limits)
      assert Model.current(model, program, c.scope, c.profile, c.limits) == :ok
      assert String.contains?(data["model_bytes"], "eq requested = #{value} .")
      # Interpret only the emitted literal transition syntax; no production model/kernel helper.
      edges =
        Regex.scan(
          ~r/rl \[([^\]]+)\] : state\(([^,]+), ([0-9]+)\) => state\(([^,]+), ([0-9]+)\) \./,
          data["model_bytes"],
          capture: :all_but_first
        )

      edges =
        Map.new(edges, fn [event, from, before, to, after_count] ->
          {{event, from, String.to_integer(before)}, {to, String.to_integer(after_count)}}
        end)

      {snapshot, time} = inputs(c, program)

      {_, _, count} =
        Enum.reduce(
          ~w(manual-first manual-repeat cancel manual-stopped cancel-repeat),
          {nil, "fresh", 0},
          fn event, {run, phase, count} ->
            {next_phase, next_count} = Map.fetch!(edges, {event, phase, count})
            kind = if event in ~w(cancel cancel-repeat), do: "cancel", else: "manual"

            assert {:ok, transition} =
                     Kernel.advance(
                       program,
                       %{
                         "kind" => kind,
                         "original" => "original:1",
                         "program_digest" => program.data["ir_digest"]
                       },
                       snapshot,
                       time,
                       %{"original" => run, "busy" => nil, "edge" => nil},
                       c.profile,
                       c.limits
                     )

            assert count + length(transition["proposals"]) == next_count
            assert transition["run"]["spent"] == []

            for proposal <- transition["proposals"],
                do: assert(proposal["input"] == source["steps"]["input"])

            assert transition["outcome"] == "cancelled" == (next_phase == "cancelled")
            {transition["run"], next_phase, next_count}
          end
        )

      assert count == 1

      schema =
        c.root
        |> Path.join("schemas/wro-04-model.schema.json")
        |> File.read!()
        |> JSON.decode!()
        |> ExJsonSchema.Schema.resolve()

      assert ExJsonSchema.Validator.validate(schema, c.scope) == :ok
      assert ExJsonSchema.Validator.validate(schema, data) == :ok
    end
  end

  test "unknown predicates, timers and composed/parameterized sources are never no-op models", c do
    sources = [
      put_in(c.source, ["condition", "value"], "unknown"),
      put_in(c.source, ["condition", "value"], false),
      %{
        c.source
        | "trigger" => %{
            "kind" => "due",
            "schedule_id" => "schedule:1",
            "schedule_basis" => "sha256:" <> String.duplicate("6", 64)
          }
      },
      %{c.source | "steps" => %{"id" => "pause", "kind" => "delay", "duration_ms" => 1}},
      %{
        c.source
        | "steps" => %{
            "id" => "wait",
            "kind" => "wait",
            "condition" => c.source["condition"],
            "timeout_ms" => 1
          }
      },
      %{
        c.source
        | "steps" => %{"id" => "parallel", "kind" => "parallel", "branches" => [c.source["steps"]]}
      },
      %{
        c.source
        | "steps" => %{"id" => "sequence", "kind" => "sequence", "steps" => [c.source["steps"]]}
      }
    ]

    for source <- sources do
      {:ok, program} = Compiler.compile(source, c.context, c.profile, c.limits)

      assert {:error, %Error{code: :unsupported_model_scope}} =
               Model.compile(program, c.scope, c.profile, c.limits)
    end

    child = %{c.source | "id" => "child"}

    source = %{
      c.source
      | "steps" => %{
          "id" => "call",
          "kind" => "invoke",
          "routine_id" => "child",
          "revision" => "1",
          "arguments" => %{}
        }
    }

    {:ok, program} =
      Compiler.compile(source, %{c.context | "definitions" => [child]}, c.profile, c.limits)

    assert {:error, %Error{code: :unsupported_model_scope}} =
             Model.compile(program, c.scope, c.profile, c.limits)

    parameters = %{
      "requested" => c.basis["value"]
    }

    source = %{c.source | "parameters" => parameters}
    context = %{c.context | "arguments" => %{"requested" => false}}
    {:ok, program} = Compiler.compile(source, context, c.profile, c.limits)

    assert {:error, %Error{code: :unsupported_model_scope}} =
             Model.compile(program, c.scope, c.profile, c.limits)
  end

  test "complete current subjects and generated bytes reject stale or recomputed native artifacts",
       c do
    {:ok, program} = Compiler.compile(c.source, c.context, c.profile, c.limits)
    {:ok, model} = Model.compile(program, c.scope, c.profile, c.limits)
    policy = %{c.scope | "policy_digest" => "sha256:" <> String.duplicate("8", 64)}

    assert {:error, %Error{code: :stale_model_binding}} =
             Model.current(model, program, policy, c.profile, c.limits)

    context = %{c.context | "compiler_basis" => "sha256:" <> String.duplicate("9", 64)}
    {:ok, changed} = Compiler.compile(c.source, context, c.profile, c.limits)

    assert {:error, %Error{code: :stale_model_binding}} =
             Model.current(model, changed, c.scope, c.profile, c.limits)

    bytes = String.replace(model.data["model_bytes"], "state(proposed, 1)", "state(proposed, 2)")
    digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    forged = %{model | data: %{model.data | "model_bytes" => bytes, "model_digest" => digest}}

    assert {:error, %Error{code: :stale_or_forged_model}} =
             Model.to_map(forged, c.profile, c.limits)

    assert {:error, %Error{}} = Model.to_map(struct!(Model, data: nil), c.profile, c.limits)
  end

  test "assumptions are closed, mandatory and cannot silently widen the profile", c do
    {:ok, program} = Compiler.compile(c.source, c.context, c.profile, c.limits)

    for scope <- [
          Map.delete(c.scope, "omissions"),
          Map.put(c.scope, "admitted", true),
          %{c.scope | "time_policy" => "progress"},
          %{c.scope | "claims" => ["physical_success"]},
          %{c.scope | "omissions" => []},
          %{c.scope | "policy_digest" => nil}
        ] do
      assert {:error, %Error{}} = Model.compile(program, scope, c.profile, c.limits)
    end
  end

  defp inputs(c, program) do
    snapshot = %{
      "id" => "snapshot:1",
      "membership_generation" => "membership:1",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{"urn:cell:output" => 1, "cell:1" => 1},
      "binding_bases" => %{
        "output" => %{
          "profile_digest" => c.basis["semantic_digest"],
          "source_id" => "source:1",
          "source_epoch" => "connection:1",
          "source_time_basis" => nil
        }
      },
      "facts" => %{"output" => nil}
    }

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => 0,
      "clock_generation" => "clock:1",
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    {snapshot, time}
  end
end
