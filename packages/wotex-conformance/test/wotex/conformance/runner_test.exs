defmodule Wotex.Conformance.RunnerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Conformance.{FailingTarget, Runner, TestFixtures}

  @generated_at ~U[2026-09-02 12:00:00Z]
  @environment %{"mode" => "air_gapped", "runtime" => "otp-28"}

  setup do
    {root, archive, digest} = TestFixtures.subject_archive!()
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      archive: archive,
      digest: digest,
      corpus: TestFixtures.corpus!(),
      subject: TestFixtures.subject!(digest)
    }
  end

  test "runs a verified subject archive without exposing expectations or inherited environment",
       context do
    System.put_env("WOTEX_CONFORMANCE_SHOULD_NOT_LEAK", "present-in-runner")
    on_exit(fn -> System.delete_env("WOTEX_CONFORMANCE_SHOULD_NOT_LEAK") end)

    target = TestFixtures.external_target!(context.archive, "pass")

    assert {:ok, report} = run(context, target)

    assert report.summary ==
             status_counts(context.corpus, pass: length(context.corpus.vectors))

    assert Enum.all?(report.results, &(&1.status == :pass))
    assert Enum.all?(report.results, &is_binary(&1.actual_digest))
    assert {:ok, encoded} = Wotex.Conformance.Report.encode(report)
    refute String.contains?(encoded, "Minimal Thing")
    refute String.contains?(encoded, "example:profile")
  end

  test "an independent target derives the Thing Model corpus observations", context do
    corpus = TestFixtures.thing_model_corpus!()
    target = TestFixtures.external_target!(context.archive, "pass")

    assert {:ok, report} =
             Runner.run(corpus, context.subject, target,
               generated_at: @generated_at,
               environment: @environment
             )

    assert report.summary == status_counts(corpus, pass: length(corpus.vectors))
  end

  test "records an observation that is not normalized as an infrastructure error", context do
    target = TestFixtures.external_target!(context.archive, "unnormalized")
    selected = hd(context.corpus.vectors).id

    assert {:ok, report} = run(context, target, select: {:ids, [selected]})
    assert report.summary == status_counts(context.corpus, infrastructure_error: 1)

    result = Enum.find(report.results, &(&1.vector_id == selected))
    assert result.code == "invalid_target_observation"
    assert is_nil(result.actual_digest)
  end

  test "classifies a valid non-matching observation as fail", context do
    target = TestFixtures.external_target!(context.archive, "mismatch")
    selected = hd(context.corpus.vectors).id

    assert {:ok, report} = run(context, target, select: {:ids, [selected]})
    assert report.summary == status_counts(context.corpus, fail: 1)
    assert Enum.find(report.results, &(&1.vector_id == selected)).code == "exact_mismatch"
  end

  test "keeps unsupported distinct from fail and infrastructure error", context do
    target = TestFixtures.external_target!(context.archive, "unsupported")
    selected = hd(context.corpus.vectors).id

    assert {:ok, report} = run(context, target, select: {:ids, [selected]})
    assert report.summary == status_counts(context.corpus, unsupported: 1)

    result = Enum.find(report.results, &(&1.vector_id == selected))
    assert result.code == "operation_not_implemented"
    assert is_nil(result.actual_digest)
  end

  test "classifies malformed output, wrong vector, non-zero exit, timeout, and output limit",
       context do
    cases = [
      {"malformed", [], "invalid_target_json"},
      {"wrong_vector", [], "target_vector_mismatch"},
      {"nonzero", [], "target_exit_nonzero"},
      {"sleep", [sleep_ms: 100, timeout_ms: 20], "target_timeout"},
      {"oversized", [max_output_bytes: 128], "target_output_limit"}
    ]

    selected = hd(context.corpus.vectors).id

    for {mode, target_options, code} <- cases do
      target = TestFixtures.external_target!(context.archive, mode, target_options)
      assert {:ok, report} = run(context, target, select: {:ids, [selected]})
      assert report.summary == status_counts(context.corpus, infrastructure_error: 1)
      assert Enum.find(report.results, &(&1.vector_id == selected)).code == code
    end
  end

  test "artifact mismatch starts no target and records selected infrastructure errors", context do
    marker = Path.join(context.root, "target-invoked")
    target = TestFixtures.external_target!(context.archive, "pass", marker_path: marker)

    wrong_subject =
      TestFixtures.subject!(
        "sha256:0000000000000000000000000000000000000000000000000000000000000000"
      )

    assert {:ok, report} =
             Runner.run(context.corpus, wrong_subject, target,
               generated_at: @generated_at,
               environment: @environment
             )

    assert report.summary ==
             status_counts(context.corpus,
               infrastructure_error: length(context.corpus.vectors)
             )

    assert Enum.all?(report.results, &(&1.code == "artifact_digest_mismatch"))
    refute File.exists?(marker)
  end

  test "rejects unknown vector selections before invoking a target", context do
    marker = Path.join(context.root, "target-invoked")
    target = TestFixtures.external_target!(context.archive, "pass", marker_path: marker)

    assert {:error, %{code: :invalid_selection}} =
             run(context, target, select: {:ids, ["unknown.vector"]})

    refute File.exists?(marker)
  end

  test "contains consumer callback failures as typed infrastructure outcomes", context do
    selected = hd(context.corpus.vectors).id

    target =
      {FailingTarget,
       %{
         artifact_path: context.archive,
         failure: :invoke
       }}

    assert {:ok, report} = run(context, target, select: {:ids, [selected]})
    assert report.summary == status_counts(context.corpus, infrastructure_error: 1)
    assert Enum.find(report.results, &(&1.vector_id == selected)).code == "target_callback_failed"

    assert {:error, %{code: :target_artifact_callback_failed}} =
             run(context, {FailingTarget, %{failure: :artifact}})
  end

  defp run(context, target, options \\ []) do
    Runner.run(
      context.corpus,
      context.subject,
      target,
      Keyword.merge(
        [generated_at: @generated_at, environment: @environment],
        options
      )
    )
  end

  defp status_counts(corpus, overrides) do
    overrides = Map.new(overrides)

    completed =
      [:pass, :fail, :unsupported, :infrastructure_error]
      |> Enum.sum_by(&Map.get(overrides, &1, 0))

    %{
      pass: 0,
      fail: 0,
      unsupported: 0,
      not_run: length(corpus.vectors) - completed,
      infrastructure_error: 0
    }
    |> Map.merge(overrides)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end
end
