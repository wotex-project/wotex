defmodule Wotex.Routines.Analysis do
  @moduledoc """
  Explicit, deadline-bound execution of regenerated inert proposal-prefix models.

  The consumer owns the task, bounded queue and concurrency. Establish the VM
  monotonic deadline before queueing; preparation and both disposable searches
  share it. Results never authorize admission. ExMaude 0.5.0 is optional and the
  interpreter is supplied explicitly. No persistent worker starts on loading.
  """

  alias Wotex.Routines.{AnalysisExecution, AnalysisRequest, AnalysisResult, Error, Limits, Profile}

  @doc "Runs only installed queries against a current model and its complete expected evidence binding."
  @spec run(term(), term(), term(), Profile.t(), Limits.t()) ::
          {:ok, AnalysisResult.t()} | {:error, Error.t()}
  def run(model, request, options, profile, limits) do
    entered = System.monotonic_time(:millisecond)

    with :ok <- options(options),
         {:ok, prepared} <- AnalysisRequest.prepare(model, request, profile, limits) do
      deadline = min(options.deadline_ms, entered + request["effective_limits"]["total_ms"])
      AnalysisExecution.run(prepared, options.maude_path, deadline, &search/3)
    end
  end

  defp options(options)
       when is_map(options) and not is_struct(options) and map_size(options) == 2 do
    path = options[:maude_path]

    valid =
      Enum.sort(Map.keys(options)) == [:deadline_ms, :maude_path] and
        is_integer(options[:deadline_ms]) and is_binary(path) and byte_size(path) in 1..4096 and
        String.valid?(path) and not String.contains?(path, <<0>>) and Path.type(path) == :absolute

    if valid, do: :ok, else: Error.refusal(:invalid_analysis_options)
  end

  defp options(_), do: Error.refusal(:invalid_analysis_options)

  defp search(bytes, query, options) do
    if File.regular?(Keyword.fetch!(options, :maude_path)) and
         Code.ensure_loaded?(ExMaude.Verification.SearchRun) and
         to_string(Application.spec(:ex_maude, :vsn)) == "0.5.0" do
      arguments = [bytes, query, options]
      apply(ExMaude.Verification.SearchRun, :run, arguments)
    else
      {:error, :unavailable}
    end
  rescue
    _ -> {:error, :backend_error}
  catch
    _, _ -> {:error, :backend_error}
  end
end
