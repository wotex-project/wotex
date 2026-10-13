defmodule Wotex.Routines.AnalysisResultTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Routines.{AnalysisResult, Error, Limits}

  setup_all do
    corpus =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("vectors/wro-01.json")
      |> File.read!()
      |> JSON.decode!()

    {:ok, limits} = Limits.new(corpus["limits"])

    binding =
      Map.new(
        ~w(scope_digest model_digest source_digest ir_digest compiler_basis behaviour_digest mapping_digest runtime_digest policy_digest time_basis_digest budget_digest),
        &{&1, "sha256:" <> String.duplicate("7", 64)}
      )

    raw = %{
      "format" => "wotex.routines.analysis.result@1",
      "binding" => binding,
      "validity" => "valid",
      "findings" => [],
      "execution" => "completed_bounded",
      "admission" => "inconclusive",
      "reason" => nil,
      "counts" => %{"states" => 1, "transitions" => 0},
      "effective_limits" => %{
        "total_ms" => 1000,
        "max_states" => 100,
        "max_transitions" => 1000,
        "max_depth" => 64,
        "max_model_bytes" => 65_536,
        "max_output_bytes" => 65_536
      }
    }

    {:ok, bytes} = Wotex.JSON.encode(raw["effective_limits"])
    digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    raw = put_in(raw, ["binding", "budget_digest"], digest)
    %{limits: limits, raw: raw}
  end

  test "completed bounded absence remains inconclusive even at zero states", c do
    assert {:ok, result} = AnalysisResult.new(c.raw, c.limits)
    assert AnalysisResult.to_map(result, c.limits) == {:ok, c.raw}

    schema =
      :wotex_routines
      |> :code.priv_dir()
      |> List.to_string()
      |> Path.join("schemas/wro-04-result.schema.json")
      |> File.read!()
      |> JSON.decode!()
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, c.raw) == :ok
    assert {:ok, _} = AnalysisResult.new(put_in(c.raw, ["counts", "states"], 0), c.limits)

    assert {:error, %Error{code: :unsupported_value}} =
             AnalysisResult.new(%{c.raw | "admission" => "admitted"}, c.limits)

    assert {:error, %Error{code: :invalid_analysis_axes}} =
             AnalysisResult.new(%{c.raw | "admission" => "blocked"}, c.limits)
  end

  test "abstract witnesses remain inconclusive and validated negative evidence retains its own completion axis",
       c do
    witness = %{
      "kind" => "counterexample",
      "property" => "no_repeated_step",
      "trace_digest" => "sha256:" <> String.duplicate("8", 64),
      "concrete" => "unvalidated"
    }

    abstract = %{c.raw | "findings" => [witness], "reason" => "incomplete"}
    assert {:ok, _} = AnalysisResult.new(abstract, c.limits)

    assert {:error, %Error{code: :invalid_analysis_axes}} =
             AnalysisResult.new(%{abstract | "admission" => "blocked"}, c.limits)

    concrete = %{
      abstract
      | "findings" => [%{witness | "concrete" => "validated"}],
        "admission" => "blocked",
        "reason" => "counterexample",
        "execution" => "truncated"
    }

    assert {:ok, result} = AnalysisResult.new(concrete, c.limits)
    assert result.data["execution"] == "truncated"

    assert {:error, %Error{code: :invalid_analysis_axes}} =
             AnalysisResult.new(%{concrete | "admission" => "inconclusive"}, c.limits)
  end

  test "unavailable, timeout, unsupported and invalid axes cannot retain findings or imply completion",
       c do
    for execution <- ~w(timeout unavailable truncated error) do
      raw = %{
        c.raw
        | "execution" => execution,
          "counts" => %{"states" => nil, "transitions" => nil},
          "reason" => "incomplete"
      }

      assert {:ok, _} = AnalysisResult.new(raw, c.limits)
    end

    raw = %{
      c.raw
      | "validity" => "unsupported",
        "execution" => "unsupported",
        "counts" => %{"states" => nil, "transitions" => nil},
        "reason" => "scope_unsupported"
    }

    assert {:ok, _} = AnalysisResult.new(raw, c.limits)

    assert {:error, %Error{code: :invalid_analysis_axes}} =
             AnalysisResult.new(
               %{raw | "execution" => "completed_bounded", "counts" => c.raw["counts"]},
               c.limits
             )

    invalid = %{raw | "validity" => "invalid", "execution" => "error", "reason" => "model_invalid"}
    assert {:ok, _} = AnalysisResult.new(invalid, c.limits)

    assert {:error, %Error{code: :invalid_analysis_axes}} =
             AnalysisResult.new(%{invalid | "execution" => "truncated"}, c.limits)
  end

  test "every correspondence subject is required and separately invalidates reuse", c do
    {:ok, result} = AnalysisResult.new(c.raw, c.limits)
    assert AnalysisResult.current(result, c.raw["binding"], c.limits) == :ok

    for key <- Map.keys(c.raw["binding"]) do
      changed = Map.put(c.raw["binding"], key, "sha256:" <> String.duplicate("9", 64))

      assert {:error, %Error{code: :stale_analysis_evidence}} =
               AnalysisResult.current(result, changed, c.limits)

      assert {:error, %Error{code: :missing_field}} =
               AnalysisResult.current(result, Map.delete(changed, key), c.limits)
    end
  end

  test "closed shapes, duplicate witnesses and selected budgets refuse malformed native values",
       c do
    witness = %{
      "kind" => "counterexample",
      "property" => "no_repeated_step",
      "trace_digest" => "sha256:" <> String.duplicate("8", 64),
      "concrete" => "unvalidated"
    }

    for raw <- [
          Map.delete(c.raw, "reason"),
          Map.put(c.raw, "safe", true),
          put_in(c.raw, ["effective_limits", "max_depth"], 257),
          put_in(c.raw, ["effective_limits", "max_states"], 0),
          put_in(c.raw, ["counts", "states"], 101),
          put_in(c.raw, ["counts", "states"], nil),
          %{c.raw | "findings" => [witness, witness]},
          %{c.raw | "findings" => [Map.put(witness, "extra", true)]},
          struct!(AnalysisResult, data: nil)
        ] do
      assert {:error, %Error{}} = AnalysisResult.new(raw, c.limits)
    end
  end

  test "changed effective budget cannot retain a previous correspondence binding", c do
    raw = put_in(c.raw, ["effective_limits", "max_depth"], 63)
    assert {:error, %Error{code: :analysis_budget_mismatch}} = AnalysisResult.new(raw, c.limits)
  end
end
