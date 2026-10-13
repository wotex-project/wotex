defmodule Wotex.Routines.ReceiptModelTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{
    Analysis,
    Basis,
    Compiler,
    Error,
    Kernel,
    Limits,
    Model,
    Profile,
    SourceTransitionOracle
  }

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
      |> Path.join("vectors/wro-04-receipt-prefix.json")
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

  test "emitted receipt rules agree with public kernel and independent source AST", c do
    paths = [
      ~w(manual-first manual-proposed held held-repeat-reserved handoff handoff-repeat ack ack-repeat match-after-ack manual-completed cancel-completed),
      ~w(manual-first held handoff match manual-completed cancel-completed),
      ~w(manual-first refused manual-refused cancel-refused),
      ~w(manual-first held handoff failed manual-failed cancel-failed),
      ~w(manual-first held handoff unknown manual-unknown cancel-unknown),
      ~w(manual-first cancel-proposed manual-cancelled cancel-cancelled),
      ~w(manual-first held cancel-reserved manual-cancelled cancel-cancelled),
      ~w(manual-first held handoff cancel-handed manual-unknown cancel-unknown),
      ~w(manual-first held handoff ack cancel-acked manual-unknown cancel-unknown)
    ]

    for value <- [false, true], labels <- paths do
      source = put_in(c.source, ["steps", "input"], value)
      {:ok, program} = Compiler.compile(source, c.context, c.profile, c.limits)
      assert {:ok, model} = Model.compile(program, c.scope, c.profile, c.limits)
      {:ok, data} = Model.to_map(model, c.profile, c.limits)
      assert String.contains?(data["model_bytes"], "eq requested = #{value} .")
      rules = parse(data["model_bytes"])

      oracle =
        SourceTransitionOracle.new(source, [], %{"output" => c.basis["timing"]["deadline_ms"]})

      {snapshot, time} = inputs(c, program)
      initial = ~w(fresh 0 0 false none false)

      Enum.reduce(labels, {nil, oracle, initial, 0}, fn label, {run, oracle, state, count} ->
        event = event(c, program, label)
        assert {:ok, oracle, proposed} = SourceTransitionOracle.advance(oracle, event, time, %{})

        assert {:ok, result} =
                 Kernel.advance(
                   program,
                   event,
                   snapshot,
                   time,
                   %{"original" => run, "busy" => nil, "edge" => nil},
                   c.profile,
                   c.limits
                 )

        next = rewrite(rules, state, label)
        count = count + length(result["proposals"])
        view = SourceTransitionOracle.view(oracle, proposed)
        expected = view_state(result["run"], count)
        assert next == expected, label
        assert next == view_state(view, count), label
        assert length(proposed) == length(result["proposals"])
        for proposal <- result["proposals"], do: assert(proposal["input"] == value)
        {result["run"], oracle, next, count}
      end)

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

  test "unsupported receipt threshold and old analysis runner never acquire this scope", c do
    {:ok, program} = Compiler.compile(c.source, c.context, c.profile, c.limits)
    {:ok, model} = Model.compile(program, c.scope, c.profile, c.limits)

    request = %{
      "format" => "wotex.routines.analysis.request@1",
      "binding" => %{},
      "effective_limits" => %{},
      "runtime" => %{},
      "time_basis" => %{}
    }

    options = %{maude_path: "/explicit", deadline_ms: System.monotonic_time(:millisecond) + 1000}

    assert {:error, %Error{code: :unsupported_analysis_scope}} =
             Analysis.run(model, request, options, c.profile, c.limits)

    source = put_in(c.source, ["steps", "completion"], "protocol_response")
    basis = put_in(c.basis, ["evidence", "completion"], "protocol_response")
    {:ok, digest} = Basis.semantic_digest(basis, c.limits)
    basis = %{basis | "semantic_digest" => digest}
    context = %{c.context | "bases" => List.replace_at(c.context["bases"], 2, basis)}

    registry =
      Enum.map(context["registry"], fn record ->
        if record["id"] == basis["id"], do: %{record | "semantic_digest" => digest}, else: record
      end)

    context = %{context | "registry" => registry}
    context = put_in(context, ["bindings", "output", "basis", "semantic_digest"], digest)
    {:ok, program} = Compiler.compile(source, context, c.profile, c.limits)

    assert {:error, %Error{code: :unsupported_model_scope}} =
             Model.compile(program, c.scope, c.profile, c.limits)

    bytes =
      String.replace(
        model.data["model_bytes"],
        "state(handed, 1, 1, true, ack, false)",
        "state(completed, 1, 1, true, ack, true)"
      )

    forged = %{
      model
      | data: %{
          model.data
          | "model_bytes" => bytes,
            "model_digest" => "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
        }
    }

    assert {:error, %Error{code: :stale_or_forged_model}} =
             Model.to_map(forged, c.profile, c.limits)
  end

  defp parse(bytes) do
    Regex.scan(
      ~r/rl \[([^\]]+)\] : state\(([^)]+)\) => state\(([^)]+)\) \./,
      bytes,
      capture: :all_but_first
    )
    |> Map.new(fn [label, left, right] ->
      {label, {String.split(left, ", "), String.split(right, ", ")}}
    end)
  end

  defp rewrite(rules, state, label) do
    {left, right} = Map.fetch!(rules, label)

    substitutions =
      Enum.zip(left, state)
      |> Enum.reduce(%{}, fn {pattern, value}, found ->
        if String.contains?(pattern, ":"), do: Map.put(found, pattern, value), else: found
      end)

    assert Enum.map(left, &Map.get(substitutions, &1, &1)) == state
    Enum.map(right, &Map.get(substitutions, &1, &1))
  end

  defp view_state(run, count) do
    step = hd(run["steps"])
    phase = if step["status"] == "handed_off", do: "handed", else: step["status"]
    receipts = step["receipts"]

    evidence =
      cond do
        match?(%{"outcome" => "accepted"}, receipts["reported_match"]) -> "match"
        match?(%{"outcome" => "accepted"}, receipts["protocol_response"]) -> "ack"
        true -> "none"
      end

    status = run["status"] || run["outcome"]
    stopped = status in ~w(partial completed refused failed unknown cancelled expired)

    [
      phase,
      to_string(count),
      to_string(length(run["spent"])),
      to_string(receipts["handoff"] != nil),
      evidence,
      to_string(stopped)
    ]
  end

  defp event(c, program, label) do
    base = %{"original" => "original:one", "program_digest" => program.data["ir_digest"]}

    cond do
      String.starts_with?(label, "manual") ->
        Map.put(base, "kind", "manual")

      String.starts_with?(label, "cancel") ->
        Map.put(base, "kind", "cancel")

      String.starts_with?(label, "held") ->
        Map.merge(base, %{
          "kind" => "admission",
          "path" => [],
          "ref" => "receipt:held",
          "outcome" => "held"
        })

      label == "refused" ->
        Map.merge(base, %{
          "kind" => "admission",
          "path" => [],
          "ref" => "receipt:refused",
          "outcome" => "refused"
        })

      String.starts_with?(label, "handoff") ->
        Map.merge(base, %{"kind" => "handoff", "path" => [], "ref" => "receipt:handoff"})

      true ->
        result(c, base, label)
    end
  end

  defp result(c, base, label) do
    stage = if String.starts_with?(label, "match"), do: "reported_match", else: "protocol_response"
    outcome = if label in ~w(failed unknown), do: label, else: "accepted"
    ref = if label == "ack-repeat", do: "ack", else: label

    Map.merge(base, %{
      "kind" => "result",
      "path" => [],
      "ref" => "receipt:" <> ref,
      "outcome" => outcome,
      "stage" => stage,
      "report_contract" => if(stage == "reported_match", do: c.basis["evidence"]["report_contract"])
    })
  end

  defp inputs(c, program) do
    snapshot = %{
      "id" => "snapshot:one",
      "membership_generation" => "membership:one",
      "active_programs" => [program.data["ir_digest"]],
      "resource_revisions" => %{"urn:cell:output" => 1, "cell:1" => 1},
      "binding_bases" => %{
        "output" => %{
          "profile_digest" => c.basis["semantic_digest"],
          "source_id" => "output:one",
          "source_epoch" => "connection:one",
          "source_time_basis" => nil
        }
      },
      "facts" => %{"output" => nil}
    }

    time = %{
      "epoch" => "boot:one",
      "clock_generation" => "clock:one",
      "elapsed_ms" => 20,
      "utc_low_ms" => nil,
      "utc_high_ms" => nil
    }

    {snapshot, time}
  end
end
