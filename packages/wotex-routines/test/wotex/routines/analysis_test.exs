defmodule Wotex.Routines.AnalysisTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.{
    Analysis,
    AnalysisExecution,
    AnalysisRequest,
    AnalysisResult,
    Compiler,
    Error,
    Limits,
    Model,
    Profile
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

  setup c do
    {:ok, program} = Compiler.compile(c.source, c.context, c.profile, c.limits)
    {:ok, model} = Model.compile(program, c.scope, c.profile, c.limits)
    request = request(model)
    {:ok, prepared} = AnalysisRequest.prepare(model, request, c.profile, c.limits)
    %{model: model, request: request, prepared: prepared}
  end

  test "every expected subject and the entire native model are checked before any backend", c do
    for key <- Map.keys(c.request["binding"]) do
      changed = put_in(c.request, ["binding", key], digest("changed"))

      assert {:error, %Error{code: :stale_analysis_binding}} =
               Analysis.run(c.model, changed, options(), c.profile, c.limits)
    end

    forged = put_in(c.model.data, ["model_bytes"], "untrusted include text")
    forged = Map.put(forged, "model_digest", digest(forged["model_bytes"]))

    assert {:error, %Error{code: :stale_or_forged_model}} =
             Analysis.run(forged, c.request, options(), c.profile, c.limits)

    for invalid <- [
          Map.put(c.request, "extra", true),
          Map.delete(c.request, "runtime"),
          put_in(c.request, ["time_basis", "elapsed_ms"], -1)
        ] do
      assert {:error, %Error{}} = Analysis.run(c.model, invalid, options(), c.profile, c.limits)
    end

    for invalid <- [
          %{},
          %{maude_path: "relative", deadline_ms: 0},
          Map.put(options(), :raw_query, "untrusted")
        ] do
      assert {:error, %Error{code: :invalid_analysis_options}} =
               Analysis.run(c.model, c.request, invalid, c.profile, c.limits)
    end
  end

  test "queue expiry returns timeout without invoking backend or retaining findings", c do
    expired = System.monotonic_time(:millisecond) - 1
    no_backend = fn _, _, _ -> flunk("expired work reached backend") end
    assert {:ok, result} = AnalysisExecution.run(c.prepared, "/unused", expired, no_backend)
    assert result.data["execution"] == "timeout"
    assert result.data["findings"] == []
    assert result.data["counts"] == %{"states" => nil, "transitions" => nil}

    assert {:ok, public} =
             Analysis.run(
               c.model,
               c.request,
               %{options() | deadline_ms: expired},
               c.profile,
               c.limits
             )

    assert public == result
  end

  test "fixed search and literal queries share one deadline and never authorize", c do
    deadline = System.monotonic_time(:millisecond) + 1000
    owner = self()

    backend = fn bytes, query, opts ->
      send(owner, {:search, query, opts})
      assert bytes == c.model.data["model_bytes"]
      assert opts[:deadline_ms] == deadline
      assert opts[:timeout] in 1..1000
      assert opts[:max_response_bytes] == 65_536
      {:ok, receipt(c, query)}
    end

    assert {:ok, result} = AnalysisExecution.run(c.prepared, "/explicit", deadline, backend)

    assert_receive {:search,
                    %{
                      initial: "state(fresh, 0)",
                      pattern: "S:State",
                      max_depth: 2,
                      max_solutions: 4
                    }, _}

    assert_receive {:search, %{initial: "requested", pattern: "B:Bool"}, _}
    assert result.data["execution"] == "completed_bounded"
    assert result.data["admission"] == "inconclusive"
    assert result.data["reason"] == nil
    assert result.data["counts"] == %{"states" => 3, "transitions" => 5}
    assert AnalysisResult.current(result, c.request["binding"], c.limits) == :ok

    schema =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("schemas/wro-04-request.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, c.request) == :ok
  end

  test "budget ceilings refuse amplified work before native execution", c do
    for {key, value} <- [
          {"max_states", 2},
          {"max_transitions", 4},
          {"max_depth", 1},
          {"max_model_bytes", 1}
        ] do
      request = put_in(c.request, ["effective_limits", key], value) |> rebind_budget()
      {:ok, prepared} = AnalysisRequest.prepare(c.model, request, c.profile, c.limits)

      assert {:ok, result} =
               execute(prepared, fn _, _, _ -> flunk("over-budget work invoked backend") end)

      assert result.data["execution"] == "truncated"
      assert result.data["reason"] == "budget_exhausted"
    end

    request = put_in(c.request, ["effective_limits", "max_output_bytes"], 1) |> rebind_budget()
    {:ok, prepared} = AnalysisRequest.prepare(c.model, request, c.profile, c.limits)

    assert {:error, %Error{code: :analysis_output_bound}} =
             execute(prepared, fn _, _, _ -> {:error, :unavailable} end)
  end

  test "backend failures stay separate and clear all counts/findings", c do
    for {backend_result, expected} <- [
          {{:error, :unavailable}, "unavailable"},
          {{:error, %{type: :load_error}}, "unavailable"},
          {{:error, %{type: :timeout}}, "timeout"},
          {{:error, :crashed}, "error"},
          {{:ok, %{}}, "error"}
        ] do
      assert {:ok, result} = execute(c.prepared, fn _, _, _ -> backend_result end)
      assert result.data["execution"] == expected
      assert result.data["counts"] == %{"states" => nil, "transitions" => nil}
      assert result.data["findings"] == []
      assert result.data["admission"] == "inconclusive"
    end

    for termination <- [
          :timeout,
          :worker_loss,
          :parser_error,
          :depth_truncation,
          :solution_limit,
          :output_truncation
        ] do
      backend = fn _, query, _ -> {:ok, %{receipt(c, query) | termination: termination}} end
      assert {:ok, result} = execute(c.prepared, backend)
      assert result.data["execution"] != "completed_bounded"
    end
  end

  test "changed executable, parser, model or concrete state/literal cannot yield completion", c do
    identities = [:model_digest, :executable_digest, :executable_version, :parser_version, :backend]

    for key <- identities do
      assert {:ok, result} =
               execute(c.prepared, fn _, query, _ ->
                 {:ok, Map.put(receipt(c, query), key, "changed")}
               end)

      assert result.data["reason"] == "correspondence_failed"
    end

    for solutions <- [[], [%{substitution: %{"S:State" => "state(proposed, 2)"}}], [nil]] do
      assert {:ok, result} =
               execute(c.prepared, fn _, query, _ ->
                 {:ok, %{receipt(c, query) | solutions: solutions}}
               end)

      assert result.data["reason"] == "correspondence_failed"
    end

    backend = fn _, query, _ ->
      receipt = receipt(c, query)

      if query.initial == "requested",
        do: {:ok, %{receipt | solutions: [%{substitution: %{"B:Bool" => "true"}}]}},
        else: {:ok, receipt}
    end

    assert {:ok, result} = execute(c.prepared, backend)
    assert result.data["reason"] == "correspondence_failed"
  end

  test "late results expire across queries and result construction", c do
    deadline = System.monotonic_time(:millisecond) + 20

    backend = fn _, query, _ ->
      Process.sleep(25)
      {:ok, receipt(c, query)}
    end

    assert {:ok, result} = AnalysisExecution.run(c.prepared, "/explicit", deadline, backend)
    assert result.data["execution"] == "timeout"
    assert result.data["counts"] == %{"states" => nil, "transitions" => nil}
  end

  defp execute(prepared, backend),
    do:
      AnalysisExecution.run(
        prepared,
        "/explicit",
        System.monotonic_time(:millisecond) + 1000,
        backend
      )

  defp options,
    do: %{maude_path: "/explicit", deadline_ms: System.monotonic_time(:millisecond) + 1000}

  defp receipt(c, query) do
    solutions =
      if query.initial == "requested",
        do: [%{substitution: %{"B:Bool" => "false"}}],
        else:
          Enum.map(
            ["state(fresh, 0)", "state(proposed, 1)", "state(cancelled, 1)"],
            &%{substitution: %{"S:State" => &1}}
          )

    %{
      model_digest: c.model.data["model_digest"],
      executable_digest: c.request["runtime"]["executable_digest"],
      executable_version: "3.5.1",
      parser_version: "ex_maude.search-run.v3",
      backend: :port,
      termination: :completed_declared_bound,
      solutions: solutions,
      error: nil
    }
  end

  defp request(model) do
    program = model.data["program"]
    context = program["context"]

    runtime = %{
      "ex_maude_version" => "0.5.0",
      "ex_maude_digest" => digest("selected package closure"),
      "executable_digest" => digest("selected interpreter"),
      "executable_version" => "3.5.1",
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
      "total_ms" => 1000,
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

  defp rebind_budget(request),
    do: put_in(request, ["binding", "budget_digest"], hash(request["effective_limits"]))

  defp hash(value) do
    {:ok, bytes} = Wotex.JSON.encode(value)
    digest(bytes)
  end

  defp digest(bytes), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
