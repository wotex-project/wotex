defmodule Wotex.Lab.ConformanceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.{Corpus, Report, Runner, Subject}
  alias Wotex.Conformance.Target.External
  alias Wotex.Lab.Conformance.Target

  @generated_at ~U[2026-09-07 12:00:00Z]

  setup_all do
    tmp =
      Path.join(System.tmp_dir!(), "wotex-lab-conformance-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    archive = Path.join(tmp, "core-ebin.tar")

    :ok =
      :erl_tar.create(
        String.to_charlist(archive),
        [{~c"ebin", String.to_charlist(Application.app_dir(:wotex, "ebin"))}],
        [:compressed]
      )

    digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, File.read!(archive)), case: :lower)

    {:ok, subject} =
      Subject.from_map(%{
        "id" => "wotex.core",
        "version" => to_string(Application.spec(:wotex, :vsn)),
        "artifact_digest" => digest,
        "interface" => %{"kind" => "lab_target", "revision" => "1"}
      })

    on_exit(fn -> File.rm_rf!(tmp) end)
    %{archive: archive, subject: subject, home: tmp}
  end

  test "the core package passes both corpora as an external subject", context do
    for {corpus_dir, expected} <- [{"thing-description-1.1", 14}, {"thing-model-1.1", 6}] do
      {:ok, corpus} =
        Corpus.load(Application.app_dir(:wotex_conformance, "priv/vectors/" <> corpus_dir))

      {:ok, target} = target(context, timeout_ms: 30_000)

      assert {:ok, %Report{} = report} =
               Runner.run(corpus, context.subject, target,
                 generated_at: @generated_at,
                 environment: %{"runtime" => "wotex_lab"}
               )

      failures = Enum.reject(report.results, &(&1.status == :pass))

      assert failures == [],
             "unexpected outcomes: " <>
               inspect(Enum.map(failures, &{&1.vector_id, &1.status, &1.code}))

      assert report.summary["pass"] == expected
      assert length(report.results) == expected
      assert {:ok, encoded} = Report.encode(report)
      refute encoded =~ "Minimal Thing"
    end
  end

  test "a changed archive is refused before any vector runs", context do
    {:ok, corpus} =
      Corpus.load(Application.app_dir(:wotex_conformance, "priv/vectors/thing-model-1.1"))

    {:ok, forged} =
      Subject.from_map(%{
        "id" => "wotex.core",
        "version" => "0.0.0",
        "artifact_digest" => "sha256:" <> String.duplicate("0", 64),
        "interface" => %{"kind" => "lab_target", "revision" => "1"}
      })

    {:ok, target} = target(context, timeout_ms: 30_000)

    assert {:ok, report} =
             Runner.run(corpus, forged, target, generated_at: @generated_at, environment: %{})

    assert report.summary["infrastructure_error"] == length(corpus.vectors)
  end

  test "the derivation is pure and reports unsupported operations and non-object documents" do
    request = fn operation, input ->
      %{"claim" => %{"operation" => operation}, "vector" => %{"id" => "v", "input" => input}}
    end

    document = %{
      "@context" => Wotex.td_context_1_1(),
      "title" => "Lamp",
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
    }

    assert %{
             "outcome" => "observed",
             "actual" => %{"accepted" => true, "document" => %{"/title" => "Lamp"}}
           } =
             Target.respond(
               request.("thing_description.parse", %{
                 "document" => document,
                 "projection" => ["/title", "/missing"]
               })
             )

    assert %{"actual" => %{"accepted" => true, "document" => ^document}} =
             Target.respond(
               request.("thing_description.validate", %{"document" => document, "projection" => []})
             )

    assert %{
             "actual" => %{
               "accepted" => false,
               "errors" => [
                 %{"code" => "schema_violation", "path" => "/title", "phase" => "schema"}
               ]
             }
           } =
             Target.respond(
               request.("thing_description.validate", %{
                 "document" => Map.delete(document, "title"),
                 "projection" => []
               })
             )

    assert %{"actual" => %{"accepted" => false, "errors" => [%{"code" => "object_required"}]}} =
             Target.respond(request.("thing_model.parse", %{"document" => "not-an-object"}))

    assert %{"outcome" => "unsupported", "codes" => ["operation_not_implemented"]} =
             Target.respond(request.("discovery.list", %{}))

    assert %{"outcome" => "unsupported", "codes" => ["invalid_request"]} = Target.respond(%{})
  end

  test "the process entry maps argument, input and decoding failures to exit codes", context do
    request = ~s({"claim":{"operation":"discovery.list"},"vector":{"id":"v","input":{}}})
    assert {:ok, encoded} = Target.run(["--archive", context.archive], fn -> request <> "\n" end)
    assert encoded =~ ~s("outcome":"unsupported")
    assert {:error, 11} = Target.run([], fn -> request end)

    assert {:error, 12} =
             Target.run(["--archive", Path.join(context.home, "missing")], fn -> request end)

    assert {:error, 13} = Target.run(["--archive", context.archive], fn -> :eof end)
    assert {:error, 14} = Target.run(["--archive", context.archive], fn -> "[not an object]" end)
    assert {:error, 14} = Target.run(["--archive", context.archive], fn -> "{" end)
  end

  defp target(context, options) do
    erl = Path.join([to_string(:code.root_dir()), "bin", "erl"])

    paths =
      Enum.flat_map(
        [:elixir, :wotex, :jason, :ex_json_schema, :wotex_lab, :wotex_runtime, :nx, :telemetry],
        fn app ->
          ["-pa", to_string(:code.lib_dir(app, :ebin))]
        end
      )

    eval =
      "application:ensure_all_started(elixir), " <>
        "'Elixir.Wotex.Lab.Conformance.Target':main([unicode:characters_to_binary(A) || A <- init:get_plain_arguments()])"

    External.from_map(%{
      executable: erl,
      args: ["-noshell"] ++ paths ++ ["-eval", eval, "-extra", "--archive", "{subject_archive}"],
      artifact_path: context.archive,
      environment: %{"HOME" => context.home},
      timeout_ms: Keyword.get(options, :timeout_ms, 10_000),
      max_output_bytes: 1_048_576
    })
  end
end
