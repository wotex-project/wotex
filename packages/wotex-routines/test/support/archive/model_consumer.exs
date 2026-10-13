defmodule ProposalModelArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{Analysis, Compiler, Error, Limits, Model, Profile, Witness}

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
      "compiler_basis" => System.fetch_env!("WOTEX_ROUTINES_COMPILER_BASIS")
    }

    %{
      source: source,
      context: context,
      scope: scope,
      profile: profile,
      limits: limits,
      basis: basis
    }
  end

  test "released public search facade executes both generated model literals and finite prefixes",
       c do
    for value <- [false, true] do
      {:ok, program} =
        Compiler.compile(
          put_in(c.source, ["steps", "input"], value),
          c.context,
          c.profile,
          c.limits
        )

      {:ok, model} = Model.compile(program, c.scope, c.profile, c.limits)
      receipt = search(model.data["model_bytes"], "state(fresh, 0)", "S:State", nil)
      assert receipt.termination == :completed_declared_bound
      assert length(receipt.solutions) == 3

      assert receipt.model_digest == model.data["model_digest"]

      literal = search(model.data["model_bytes"], "requested", "B:Bool", nil)
      assert length(literal.solutions) == 1
      assert hd(literal.solutions).substitution["B:Bool"] == to_string(value)

      IO.write(
        "native model runtime: #{receipt.executable_version}; " <>
          "executable sha256: #{receipt.executable_digest}\n"
      )
    end
  end

  test "a native mutated-model counterexample cannot become a concretely validated runtime incident",
       c do
    {:ok, program} = Compiler.compile(c.source, c.context, c.profile, c.limits)
    {:ok, model} = Model.compile(program, c.scope, c.profile, c.limits)

    original =
      search(
        model.data["model_bytes"],
        "state(fresh, 0)",
        "state(P:Phase, N:Nat)",
        "N:Nat > 1 = true"
      )

    assert original.solutions == []

    assert original.termination == :completed_declared_bound,
           inspect(Map.take(original, [:error, :depth_probe]))

    mutated =
      String.replace(
        model.data["model_bytes"],
        "state(proposed, 1) => state(proposed, 1)",
        "state(proposed, 1) => state(proposed, 2)"
      )

    receipt = search(mutated, "state(fresh, 0)", "state(P:Phase, N:Nat)", "N:Nat > 1 = true")
    assert length(receipt.solutions) >= 1
    assert receipt.model_digest != original.model_digest
    frame = frame(c, program)

    witness = %{
      "format" => "wotex.routines.witness@1",
      "property" => "proposal_once",
      "program_digest" => program.data["ir_digest"],
      "source_digest" => program.data["source_digest"],
      "compiler_basis" => program.data["context"]["compiler_basis"],
      "max_steps" => 2,
      "max_originals" => 1,
      "initial" => %{"runs" => [], "edge" => nil},
      "frames" => [frame, frame]
    }

    assert {:ok, replay} = Witness.replay(program, witness, c.profile, c.limits)
    assert replay["reproduced"] == false
  end

  test "public runner binds actual native identity and all phases without positive admission", c do
    for value <- [false, true] do
      {:ok, program} =
        Compiler.compile(
          put_in(c.source, ["steps", "input"], value),
          c.context,
          c.profile,
          c.limits
        )

      {:ok, model} = Model.compile(program, c.scope, c.profile, c.limits)
      identity = search(model.data["model_bytes"], "requested", "B:Bool", nil)
      request = analysis_request(model, identity)

      options = %{
        maude_path: System.fetch_env!("WOTEX_ROUTINES_MAUDE_PATH"),
        deadline_ms: System.monotonic_time(:millisecond) + 5000
      }

      assert {:ok, result} = Analysis.run(model, request, options, c.profile, c.limits)
      assert result.data["execution"] == "completed_bounded", inspect(result)
      assert result.data["admission"] == "inconclusive"
      assert result.data["counts"] == %{"states" => 3, "transitions" => 5}
      assert result.data["findings"] == []
      expired = %{options | deadline_ms: System.monotonic_time(:millisecond) - 1}
      assert {:ok, result} = Analysis.run(model, request, expired, c.profile, c.limits)
      assert result.data["execution"] == "timeout"
      stale = put_in(request, ["binding", "runtime_digest"], digest("changed"))

      assert {:error, %Error{code: :stale_analysis_binding}} =
               Analysis.run(model, stale, options, c.profile, c.limits)
    end
  end

  test "native staged-receipt model preserves held spend and completion threshold", c do
    scope =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-04-receipt-prefix.json")
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("scope")

    {:ok, program} = Compiler.compile(c.source, c.context, c.profile, c.limits)
    {:ok, model} = Model.compile(program, scope, c.profile, c.limits)

    query = %{
      module: "ROUTINE-RECEIPT-PREFIX",
      initial: "state(fresh, 0, 0, false, none, false)",
      pattern: "S:State",
      max_depth: 8,
      max_solutions: 64
    }

    options = [
      maude_path: System.fetch_env!("WOTEX_ROUTINES_MAUDE_PATH"),
      timeout: 2000,
      max_response_bytes: 65_536,
      deadline_ms: System.monotonic_time(:millisecond) + 2000
    ]

    assert {:ok, receipt} =
             ExMaude.Verification.SearchRun.run(model.data["model_bytes"], query, options)

    assert receipt.termination == :completed_declared_bound,
           inspect(Map.take(receipt, [:error, :depth_probe]))

    states = Enum.map(receipt.solutions, &String.replace(&1.substitution["S:State"], ~r/\s+/, ""))
    assert "state(completed,1,1,true,match,true)" in states
    assert "state(unknown,1,1,true,ack,true)" in states
    refute "state(completed,1,1,true,ack,true)" in states

    mutant =
      String.replace(
        model.data["model_bytes"],
        "state(handed, 1, 1, true, none, false) => state(handed, 1, 1, true, ack, false)",
        "state(handed, 1, 1, true, none, false) => state(completed, 1, 1, true, ack, true)"
      )

    assert mutant != model.data["model_bytes"]
    counter_query = %{query | pattern: "state(completed, N:Nat, S:Nat, H:Bool, ack, true)"}
    options = Keyword.put(options, :deadline_ms, System.monotonic_time(:millisecond) + 2000)
    assert {:ok, counter} = ExMaude.Verification.SearchRun.run(mutant, counter_query, options)
    assert length(counter.solutions) >= 1
    assert counter.model_digest != model.data["model_digest"]
  end

  defp search(bytes, initial, pattern, condition) do
    query = %{
      module: "ROUTINE-PROPOSAL-PREFIX",
      initial: initial,
      pattern: pattern,
      max_depth: 8,
      max_solutions: 16
    }

    query = if condition, do: Map.put(query, :condition, condition), else: query

    assert {:ok, receipt} =
             ExMaude.Verification.SearchRun.run(bytes, query,
               maude_path: System.fetch_env!("WOTEX_ROUTINES_MAUDE_PATH"),
               timeout: 2000,
               max_response_bytes: 65_536,
               deadline_ms: System.monotonic_time(:millisecond) + 2000
             )

    receipt
  end

  defp frame(c, program) do
    %{
      "event" => %{
        "kind" => "manual",
        "original" => "original:1",
        "program_digest" => program.data["ir_digest"]
      },
      "time" => %{
        "epoch" => "boot:1",
        "elapsed_ms" => 0,
        "clock_generation" => "clock:1",
        "utc_low_ms" => nil,
        "utc_high_ms" => nil
      },
      "snapshot" => %{
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
    }
  end

  defp analysis_request(model, receipt) do
    program = model.data["program"]
    context = program["context"]

    runtime = %{
      "ex_maude_version" => "0.5.0",
      "ex_maude_digest" => digest(File.read!("mix.lock")),
      "executable_digest" => receipt.executable_digest,
      "executable_version" => receipt.executable_version,
      "parser_version" => "ex_maude.search-run.v3",
      "backend" => "port"
    }

    time = %{
      "epoch" => "boot:1",
      "elapsed_ms" => 0,
      "clock_generation" => "clock:1",
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    limits = %{
      "total_ms" => 5000,
      "max_states" => 3,
      "max_transitions" => 5,
      "max_depth" => 2,
      "max_model_bytes" => 65_536,
      "max_output_bytes" => 65_536
    }

    binding = %{
      "scope_digest" => model.data["scope_digest"],
      "model_digest" => model.data["model_digest"],
      "source_digest" => program["source_digest"],
      "ir_digest" => program["ir_digest"],
      "compiler_basis" => context["compiler_basis"],
      "behaviour_digest" => hash(context["bases"]),
      "mapping_digest" => hash(Map.take(context, ~w(registry bindings))),
      "runtime_digest" => hash(runtime),
      "policy_digest" => model.data["scope"]["policy_digest"],
      "time_basis_digest" => hash(time),
      "budget_digest" => hash(limits)
    }

    %{
      "format" => "wotex.routines.analysis.request@1",
      "binding" => binding,
      "effective_limits" => limits,
      "runtime" => runtime,
      "time_basis" => time
    }
  end

  defp hash(value) do
    {:ok, bytes} = Wotex.JSON.encode(value)
    digest(bytes)
  end

  defp digest(bytes), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
