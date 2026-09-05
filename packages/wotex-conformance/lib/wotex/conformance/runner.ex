defmodule Wotex.Conformance.Runner do
  @moduledoc """
  Verifies a subject archive, invokes an external target for selected vectors,
  evaluates observations, and emits one deterministic evidence report.

  Results are ordered by vector ID regardless of corpus file order. Archive
  verification failure is recorded as `infrastructure_error` for every selected
  vector; excluded vectors remain `not_run`.
  """

  alias Wotex.Conformance.{
    Artifact,
    Canonical,
    Corpus,
    Environment,
    Error,
    Input,
    Report,
    Result,
    Subject,
    Target,
    Vector
  }

  alias Wotex.Conformance.Target.Response

  @doc """
  Runs selected corpus vectors against a target and returns evidence.

  `:generated_at` is required so callers, rather than wall-clock access, own
  reproducibility. Optional `:select` accepts `:all` or `{:ids, ids}`;
  `:environment` supplies bounded, non-sensitive report metadata.
  """
  @spec run(Corpus.t(), Subject.t(), term(), keyword()) ::
          {:ok, Report.t()} | {:error, Error.t()}
  def run(%Corpus{} = corpus, %Subject{} = subject, target_input, options) do
    with :ok <- Input.options(options, [:generated_at, :environment, :select]),
         {:ok, generated_at} <- generated_at(options),
         {:ok, environment} <- environment(options),
         {:ok, selection} <- selection(options, corpus.vectors),
         {:ok, target} <- Target.normalize(target_input),
         {:ok, artifact_path} <- Target.artifact_path(target) do
      results =
        case Artifact.verify(artifact_path, subject.artifact_digest) do
          {:ok, _verification} ->
            run_vectors(corpus, subject, target, selection, generated_at, environment)

          {:error, error} ->
            infrastructure_results(corpus.vectors, selection, error)
        end

      Report.new(subject, corpus.digest, generated_at, environment, results)
    end
  end

  defp generated_at(options) do
    case Keyword.fetch(options, :generated_at) do
      {:ok, %DateTime{} = generated_at} ->
        case DateTime.shift_zone(generated_at, "Etc/UTC") do
          {:ok, utc} ->
            {:ok, utc}

          {:error, _reason} ->
            {:error,
             Error.new(:invalid_generated_at, "generated_at could not be normalized to UTC")}
        end

      {:ok, _value} ->
        {:error, Error.new(:invalid_generated_at, "generated_at must be a DateTime")}

      :error ->
        {:error, Error.new(:missing_generated_at, "generated_at is required")}
    end
  end

  defp environment(options) do
    options
    |> Keyword.get(:environment, %{})
    |> Environment.validate()
  end

  defp selection(options, vectors) do
    all_ids = MapSet.new(vectors, & &1.id)

    case Keyword.get(options, :select, :all) do
      :all ->
        {:ok, all_ids}

      {:ids, ids} when is_list(ids) ->
        requested = MapSet.new(ids)

        if Enum.all?(ids, &is_binary/1) and MapSet.subset?(requested, all_ids) do
          {:ok, requested}
        else
          {:error, Error.new(:invalid_selection, "selected vector IDs must exist in the corpus")}
        end

      _value ->
        {:error, Error.new(:invalid_selection, "select must be :all or {:ids, ids}")}
    end
  end

  defp run_vectors(corpus, subject, target, selection, generated_at, environment) do
    context = %{
      "corpus" => %{"id" => corpus.id, "revision" => corpus.revision, "digest" => corpus.digest},
      "generated_at" => DateTime.to_iso8601(generated_at),
      "environment" => environment
    }

    Enum.map(corpus.vectors, fn vector ->
      if MapSet.member?(selection, vector.id) do
        run_vector(vector, subject, target, context)
      else
        result!(vector, :not_run, code: "selection_excluded")
      end
    end)
  end

  defp run_vector(vector, subject, target, context) do
    request = Vector.target_request(vector, subject, context)

    case Target.invoke(target, request) do
      {:ok, %Response{outcome: :observed, actual: actual}, duration_us} ->
        evaluate_observation(vector, actual, duration_us)

      {:ok, %Response{outcome: :unsupported, codes: codes}, duration_us} ->
        result!(vector, :unsupported,
          code: List.first(codes) || "target_unsupported",
          duration_us: duration_us
        )

      {:error, %Error{} = error, duration_us} ->
        result!(vector, :infrastructure_error,
          code: Atom.to_string(error.code),
          duration_us: duration_us
        )
    end
  end

  defp evaluate_observation(vector, actual, duration_us) do
    case Canonical.digest(actual) do
      {:ok, digest} when digest == vector.expectation.digest ->
        result!(vector, :pass, actual: actual, code: "exact_match", duration_us: duration_us)

      {:ok, _digest} ->
        result!(vector, :fail, actual: actual, code: "exact_mismatch", duration_us: duration_us)

      {:error, _error} ->
        result!(vector, :infrastructure_error,
          code: "invalid_target_observation",
          duration_us: duration_us
        )
    end
  end

  defp infrastructure_results(vectors, selection, error) do
    Enum.map(vectors, fn vector ->
      if MapSet.member?(selection, vector.id) do
        result!(vector, :infrastructure_error, code: Atom.to_string(error.code))
      else
        result!(vector, :not_run, code: "selection_excluded")
      end
    end)
  end

  defp result!(vector, status, options) do
    case Result.new(vector, status, options) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end
end
