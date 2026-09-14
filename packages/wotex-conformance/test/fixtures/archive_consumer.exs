defmodule ArchiveConsumerFixture do
  @moduledoc false

  alias Wotex.Conformance.{Artifact, Corpus, Runner, Subject}
  alias Wotex.Conformance.Target.External

  @generated_at ~U[2026-09-02 12:00:00Z]
  @selected_vector "td11.parse.minimal"
  @cases [
    {"pass", :pass, "exact_match", []},
    {"mismatch", :fail, "exact_mismatch", []},
    {"unsupported", :unsupported, "operation_not_implemented", []},
    {"sleep", :infrastructure_error, "target_timeout", [sleep_ms: 200, timeout_ms: 20]},
    {"malformed", :infrastructure_error, "invalid_target_json", []}
  ]

  @spec run() :: :ok | no_return()
  def run do
    configuration = configuration!(System.argv())
    verify_isolation!(configuration)

    {:ok, corpus} =
      Corpus.load(Path.join(configuration.package, "priv/vectors/thing-description-1.1"))

    {:ok, digest} = Artifact.digest_file(configuration.subject)

    {:ok, subject} =
      Subject.from_map(%{
        id: "example.archive-subject",
        version: "1.0.0",
        artifact_digest: digest,
        interface: %{"kind" => "archive_adapter", "revision" => "1"}
      })

    results =
      Enum.map(@cases, fn {mode, expected_status, expected_code, options} ->
        target = target!(configuration, mode, options)

        {:ok, report} =
          Runner.run(corpus, subject, target,
            generated_at: @generated_at,
            environment: %{"mode" => "archive_only", "runtime" => runtime()},
            select: {:ids, [@selected_vector]}
          )

        result = Enum.find(report.results, &(&1.vector_id == @selected_vector))

        unless {result.status, result.code} == {expected_status, expected_code} do
          abort("#{mode} produced #{inspect({result.status, result.code})}")
        end

        {mode, result.status, result.code}
      end)

    :ok = load_application(:jason)
    dependency_version = :jason |> Application.spec(:vsn) |> to_string()

    IO.puts("archive consumer outcomes: #{format_results(results)}")
    IO.puts("archive consumer corpus: #{corpus.id}@#{corpus.revision} #{corpus.digest}")
    IO.puts("archive consumer runtime: #{runtime()} jason-#{dependency_version}")
  end

  defp target!(configuration, mode, options) do
    environment = %{
      "ELIXIR_ERL_OPTIONS" => "+fnu",
      "PATH" => target_path(configuration.elixir, configuration.erl),
      "TARGET_MODE" => mode,
      "TARGET_SLEEP_MS" => to_string(Keyword.get(options, :sleep_ms, 0))
    }

    {:ok, target} =
      External.from_map(%{
        executable: configuration.elixir,
        args: [configuration.target, "--archive", "{subject_archive}"],
        artifact_path: configuration.subject,
        environment: environment,
        timeout_ms: Keyword.get(options, :timeout_ms, 5_000),
        max_output_bytes: 1_048_576
      })

    target
  end

  defp verify_isolation!(configuration) do
    package = Path.expand(configuration.package)
    forbidden = Path.expand(configuration.forbid)

    source =
      Wotex.Conformance.module_info(:compile)
      |> Keyword.fetch!(:source)
      |> to_string()
      |> Path.expand()

    unless within?(source, package) do
      abort("conformance modules were not compiled from the unpacked archive")
    end

    forbidden_paths =
      :code.get_path()
      |> Enum.map(&(&1 |> to_string() |> Path.expand()))
      |> Enum.filter(&within?(&1, forbidden))

    unless forbidden_paths == [] do
      abort("consumer code path contains the source checkout")
    end

    isolated_paths = [File.cwd!(), package, configuration.target, Path.expand(__ENV__.file)]

    if Enum.any?(isolated_paths, &within?(&1, forbidden)) or
         not File.regular?(configuration.target) do
      abort("consumer fixtures were not isolated from the source checkout")
    end
  end

  defp configuration!(arguments) do
    case arguments do
      [
        "--package",
        package,
        "--target",
        target,
        "--subject",
        subject,
        "--elixir",
        elixir,
        "--erl",
        erl,
        "--forbid",
        forbid
      ] ->
        %{
          package: package,
          target: target,
          subject: subject,
          elixir: elixir,
          erl: erl,
          forbid: forbid
        }

      _ ->
        abort(
          "usage: archive_consumer.exs --package PACKAGE --target TARGET --subject SUBJECT " <>
            "--elixir ELIXIR --erl ERL --forbid ROOT"
        )
    end
  end

  defp target_path(executable, erl) do
    [Path.dirname(executable), Path.dirname(erl), "/usr/bin", "/bin"]
    |> Enum.uniq()
    |> Enum.join(":")
  end

  defp within?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp runtime do
    "elixir-#{System.version()}-otp-#{System.otp_release()}"
  end

  defp load_application(application) do
    case Application.load(application) do
      :ok -> :ok
      {:error, {:already_loaded, ^application}} -> :ok
      {:error, reason} -> abort("cannot load #{application}: #{inspect(reason)}")
    end
  end

  defp format_results(results) do
    Enum.map_join(results, ", ", fn {mode, status, code} ->
      "#{mode}=#{status}/#{code}"
    end)
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

ArchiveConsumerFixture.run()
