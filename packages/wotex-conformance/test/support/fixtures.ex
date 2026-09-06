defmodule Wotex.Conformance.TestFixtures do
  @moduledoc false

  alias Wotex.Conformance.{Artifact, Corpus, Subject}
  alias Wotex.Conformance.Target.External

  @spec corpus!() :: Corpus.t()
  def corpus! do
    path = Path.expand("../../priv/vectors/thing-description-1.1", __DIR__)
    {:ok, corpus} = Corpus.load(path)
    corpus
  end

  @spec thing_model_corpus!() :: Corpus.t()
  def thing_model_corpus! do
    path = Path.expand("../../priv/vectors/thing-model-1.1", __DIR__)
    {:ok, corpus} = Corpus.load(path)
    corpus
  end

  @spec subject_archive!() :: {Path.t(), Path.t(), String.t()}
  def subject_archive! do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-conformance-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(root)
    archive = Path.join(root, "subject.tar.gz")
    contents = ~s({"interface_revision":"1","subject":"synthetic"})

    :ok =
      :erl_tar.create(
        String.to_charlist(archive),
        [{~c"manifest.json", contents}],
        [:compressed]
      )

    {:ok, digest} = Artifact.digest_file(archive)
    {root, archive, digest}
  end

  @spec subject!(String.t()) :: Subject.t()
  def subject!(digest) do
    {:ok, subject} =
      Subject.new(%{
        id: "example.thing-description",
        version: "1.0.0",
        artifact_digest: digest,
        interface: %{"kind" => "archive_adapter", "revision" => "1"}
      })

    subject
  end

  @spec external_target!(Path.t(), String.t(), keyword()) :: External.t()
  def external_target!(archive, mode, options \\ []) do
    executable = System.find_executable("elixir")
    adapter = Path.expand("../fixtures/external_target.exs", __DIR__)

    environment =
      %{
        # The target scrubs the locale; keep VM startup warnings out of its JSON output.
        "ELIXIR_ERL_OPTIONS" => "+fnu",
        "PATH" =>
          [System.find_executable("erl") |> Path.dirname(), "/usr/bin", "/bin"]
          |> Enum.join(":"),
        "TARGET_MODE" => mode
      }
      |> maybe_put("TARGET_MARKER_PATH", Keyword.get(options, :marker_path))
      |> maybe_put("TARGET_SLEEP_MS", Keyword.get(options, :sleep_ms))

    {:ok, target} =
      External.new(%{
        executable: executable,
        args: [adapter, "--archive", "{subject_archive}"],
        artifact_path: archive,
        environment: environment,
        timeout_ms: Keyword.get(options, :timeout_ms, 5_000),
        max_output_bytes: Keyword.get(options, :max_output_bytes, 1_048_576)
      })

    target
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_string(value))
end
