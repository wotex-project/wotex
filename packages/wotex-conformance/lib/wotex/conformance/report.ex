defmodule Wotex.Conformance.Report do
  @moduledoc """
  Canonical machine-readable evidence for one subject and one corpus.

  The report digest covers all fields except itself. Given the same typed
  values, canonical bytes and digest are identical.
  """

  alias Wotex.Conformance.{Canonical, Environment, Error, Result, Subject}

  @schema_version "1.0"
  @statuses ~w(pass fail unsupported not_run infrastructure_error)

  @enforce_keys [
    :schema_version,
    :run_id,
    :subject,
    :corpus_digest,
    :generated_at,
    :environment,
    :results,
    :summary,
    :digest
  ]
  defstruct [
    :schema_version,
    :run_id,
    :subject,
    :corpus_digest,
    :generated_at,
    :environment,
    :results,
    :summary,
    :digest
  ]

  @type t :: %__MODULE__{
          schema_version: String.t(),
          run_id: String.t(),
          subject: Subject.t(),
          corpus_digest: String.t(),
          generated_at: String.t(),
          environment: map(),
          results: [Result.t()],
          summary: %{String.t() => non_neg_integer()},
          digest: String.t()
        }

  @spec new(Subject.t(), String.t(), DateTime.t(), map(), [Result.t()]) ::
          {:ok, t()} | {:error, Error.t()}
  def new(%Subject{} = subject, corpus_digest, %DateTime{} = generated_at, environment, results)
      when is_list(results) do
    with :ok <- validate_digest(corpus_digest),
         {:ok, environment} <- Environment.validate(environment),
         :ok <- validate_results(results),
         sorted_results = Enum.sort_by(results, & &1.vector_id),
         {:ok, generated_at} <- normalize_time(generated_at),
         {:ok, run_id} <- run_id(subject, corpus_digest, generated_at, environment),
         report = %__MODULE__{
           schema_version: @schema_version,
           run_id: run_id,
           subject: subject,
           corpus_digest: corpus_digest,
           generated_at: generated_at,
           environment: environment,
           results: sorted_results,
           summary: summarize(sorted_results),
           digest: ""
         },
         {:ok, digest} <- Canonical.digest(to_map(report, include_digest: false)) do
      {:ok, %{report | digest: digest}}
    end
  end

  def new(%Subject{}, _corpus_digest, _generated_at, _environment, _results) do
    {:error, Error.new(:invalid_report_input, "report inputs are invalid")}
  end

  @spec to_map(t(), keyword()) :: map()
  def to_map(%__MODULE__{} = report, options \\ []) do
    map = %{
      "schema_version" => report.schema_version,
      "run_id" => report.run_id,
      "subject" => Subject.to_map(report.subject),
      "corpus_digest" => report.corpus_digest,
      "generated_at" => report.generated_at,
      "environment" => report.environment,
      "results" => Enum.map(report.results, &Result.to_map/1),
      "summary" => report.summary
    }

    if Keyword.get(options, :include_digest, true) do
      Map.put(map, "digest", report.digest)
    else
      map
    end
  end

  @spec encode(t()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%__MODULE__{} = report), do: report |> to_map() |> Canonical.encode()

  defp validate_digest(digest) do
    if Canonical.valid_digest?(digest) do
      :ok
    else
      {:error, Error.new(:invalid_digest, "corpus digest must be lowercase SHA-256")}
    end
  end

  defp normalize_time(generated_at) do
    case DateTime.shift_zone(generated_at, "Etc/UTC") do
      {:ok, utc} ->
        {:ok, DateTime.to_iso8601(utc)}

      {:error, _reason} ->
        {:error, Error.new(:invalid_generated_at, "generated_at could not be normalized to UTC")}
    end
  end

  defp validate_results(results) do
    cond do
      not Enum.all?(results, &match?(%Result{}, &1)) ->
        {:error, Error.new(:invalid_type, "results must contain result values")}

      results |> Enum.map(& &1.vector_id) |> duplicate?() ->
        {:error, Error.new(:duplicate_vector_result, "results contain duplicate vector IDs")}

      true ->
        :ok
    end
  end

  defp duplicate?(entries), do: length(entries) != MapSet.size(MapSet.new(entries))

  defp summarize(results) do
    initial = Map.new(@statuses, &{&1, 0})

    Enum.reduce(results, initial, fn result, summary ->
      Map.update!(summary, Atom.to_string(result.status), &(&1 + 1))
    end)
  end

  defp run_id(subject, corpus_digest, generated_at, environment) do
    Canonical.digest(%{
      "subject" => Subject.to_map(subject),
      "corpus_digest" => corpus_digest,
      "generated_at" => generated_at,
      "environment" => environment
    })
  end
end
