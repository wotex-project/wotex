defmodule Wotex.Routines.AnalysisRequest do
  @moduledoc false

  alias Wotex.Routines.{
    AnalysisProfile,
    AnalysisResult,
    Error,
    Limits,
    Model,
    Profile,
    Time,
    Validation
  }

  @fields ~w(format binding effective_limits runtime time_basis)
  @runtime ~w(ex_maude_version ex_maude_digest executable_digest executable_version parser_version backend)

  @doc false
  @spec prepare(term(), term(), Profile.t(), Limits.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def prepare(model, request, profile, limits) do
    with {:ok, request, limits} <- Validation.admit(request, limits, nil),
         :ok <- Validation.fields(request, @fields),
         :ok <-
           Validation.choice(request["format"], ["wotex.routines.analysis.request@1"], "/format"),
         {:ok, model} <- Model.to_map(model, profile, limits),
         {:ok, query_profile} <- AnalysisProfile.select(model),
         :ok <- runtime(request["runtime"]),
         {:ok, time} <- Time.to_map(request["time_basis"], limits),
         {:ok, binding} <- binding(model, request, time, limits),
         :ok <- matches(binding, request["binding"]),
         {:ok, _} <- AnalysisResult.new(result(binding, request["effective_limits"]), limits) do
      {:ok,
       %{
         model: model,
         request: request,
         binding: binding,
         limits: limits,
         query_profile: query_profile
       }}
    end
  end

  defp runtime(data) do
    with :ok <- Validation.fields(data, @runtime),
         :ok <- Validation.choice(data["ex_maude_version"], ["0.5.0"], "/runtime/ex_maude_version"),
         :ok <-
           Validation.choice(
             data["parser_version"],
             ["ex_maude.search-run.v3"],
             "/runtime/parser_version"
           ),
         :ok <- Validation.choice(data["backend"], ["port"], "/runtime/backend"),
         :ok <- Validation.text(data["executable_version"], "/runtime/executable_version") do
      Validation.each(~w(ex_maude_digest executable_digest), fn key ->
        Validation.digest(data[key], "/runtime/" <> key)
      end)
    end
  end

  defp binding(model, request, time, limits) do
    program = model["program"]
    context = program["context"]

    with {:ok, behaviour} <- Validation.hash(context["bases"], limits),
         {:ok, mapping} <- Validation.hash(Map.take(context, ~w(registry bindings)), limits),
         {:ok, runtime} <- Validation.hash(request["runtime"], limits),
         {:ok, time_basis} <- Validation.hash(time, limits),
         {:ok, budget} <- Validation.hash(request["effective_limits"], limits) do
      {:ok,
       %{
         "scope_digest" => model["scope_digest"],
         "model_digest" => model["model_digest"],
         "source_digest" => program["source_digest"],
         "ir_digest" => program["ir_digest"],
         "compiler_basis" => context["compiler_basis"],
         "behaviour_digest" => behaviour,
         "mapping_digest" => mapping,
         "runtime_digest" => runtime,
         "policy_digest" => model["scope"]["policy_digest"],
         "time_basis_digest" => time_basis,
         "budget_digest" => budget
       }}
    end
  end

  defp matches(binding, binding), do: :ok
  defp matches(_, _), do: Error.refusal(:stale_analysis_binding)

  defp result(binding, limits) do
    %{
      "format" => "wotex.routines.analysis.result@1",
      "binding" => binding,
      "effective_limits" => limits,
      "validity" => "valid",
      "findings" => [],
      "execution" => "timeout",
      "admission" => "inconclusive",
      "reason" => "budget_exhausted",
      "counts" => %{"states" => nil, "transitions" => nil}
    }
  end
end
