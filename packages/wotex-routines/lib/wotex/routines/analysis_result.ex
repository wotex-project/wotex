defmodule Wotex.Routines.AnalysisResult do
  @moduledoc "Closed bounded analysis axes and complete correspondence binding. Results supply no positive admission."

  alias Wotex.Routines.{Error, Limits, Validation}

  @fields ~w(format binding validity findings execution admission reason counts effective_limits)
  @binding ~w(scope_digest model_digest source_digest ir_digest compiler_basis behaviour_digest mapping_digest runtime_digest policy_digest time_basis_digest budget_digest)
  @reasons ~w(model_invalid scope_unsupported budget_exhausted backend_unavailable counterexample incomplete correspondence_failed stale_evidence)
  @ceilings %{
    "total_ms" => 60_000,
    "max_states" => 100_000,
    "max_transitions" => 1_000_000,
    "max_depth" => 256
  }
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Checks complete axes, witness assertions, budgets and counts without authenticating supplied evidence."
  @spec new(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, @fields),
         :ok <- Validation.choice(data["format"], ["wotex.routines.analysis.result@1"], "/format"),
         :ok <- check_binding(data["binding"]),
         :ok <- axes(data),
         :ok <- findings(data["findings"]),
         :ok <- budgets(data["effective_limits"], limits),
         :ok <- budget_binding(data, limits),
         :ok <- counts(data, limits),
         :ok <- coherence(data) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Revalidates every result member before projection."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(result, limits) do
    with {:ok, result} <- new(result, limits), do: {:ok, result.data}
  end

  @doc "Compares every expected binding subject before evidence reuse; matching hashes are not authentication."
  @spec current(term(), term(), Limits.t()) :: :ok | {:error, Error.t()}
  def current(result, expected, limits) do
    with {:ok, result} <- new(result, limits),
         {:ok, expected, _} <- Validation.admit(expected, limits, nil),
         :ok <- check_binding(expected) do
      if result.data["binding"] == expected, do: :ok, else: Error.refusal(:stale_analysis_evidence)
    end
  end

  defp check_binding(data) do
    with :ok <- Validation.fields(data, @binding) do
      Validation.each(Map.values(data), &Validation.digest(&1, "/binding"))
    end
  end

  defp axes(data) do
    with :ok <- Validation.choice(data["validity"], ~w(valid invalid unsupported), "/validity"),
         :ok <-
           Validation.choice(
             data["execution"],
             ~w(completed_bounded truncated timeout unavailable unsupported error),
             "/execution"
           ),
         :ok <- Validation.choice(data["admission"], ~w(inconclusive blocked), "/admission") do
      if data["reason"] == nil,
        do: :ok,
        else: Validation.choice(data["reason"], @reasons, "/reason")
    end
  end

  defp findings(values) when is_list(values) do
    with :ok <- Validation.each(values, &finding/1) do
      identities = Enum.map(values, &{&1["property"], &1["trace_digest"]})

      if length(Enum.uniq(identities)) == length(identities),
        do: :ok,
        else: Error.refusal(:duplicate_finding)
    end
  end

  defp findings(_), do: Error.refusal(:invalid_type, "/findings")

  defp finding(data) do
    with :ok <- Validation.fields(data, ~w(kind property trace_digest concrete)),
         :ok <- Validation.choice(data["kind"], ["counterexample"], "/findings/kind"),
         :ok <- Validation.text(data["property"], "/findings/property"),
         :ok <- Validation.digest(data["trace_digest"], "/findings/trace_digest") do
      Validation.choice(data["concrete"], ~w(validated unvalidated), "/findings/concrete")
    end
  end

  defp budgets(data, limits) do
    ceilings =
      Map.merge(@ceilings, %{
        "max_model_bytes" => limits.data["max_bytes"],
        "max_output_bytes" => limits.data["max_bytes"]
      })

    with :ok <- Validation.fields(data, Map.keys(ceilings)) do
      Validation.each(Map.to_list(ceilings), fn {key, ceiling} ->
        budget(data[key], key, ceiling, limits)
      end)
    end
  end

  defp budget(value, key, ceiling, limits) do
    with :ok <- Validation.integer(value, limits, "/effective_limits/" <> key, 1) do
      if value <= ceiling, do: :ok, else: Error.refusal(:analysis_bound)
    end
  end

  defp counts(data, limits) do
    with :ok <- Validation.fields(data["counts"], ~w(states transitions)) do
      Validation.each(~w(states transitions), fn key ->
        value = data["counts"][key]

        cond do
          value == nil and data["execution"] != "completed_bounded" ->
            :ok

          not is_integer(value) ->
            Error.refusal(:invalid_analysis_count)

          value < 0 or value > data["effective_limits"]["max_" <> key] ->
            Error.refusal(:analysis_bound)

          true ->
            Validation.integer(value, limits, "/counts/" <> key, 0)
        end
      end)
    end
  end

  defp budget_binding(data, limits) do
    with {:ok, digest} <- Validation.hash(data["effective_limits"], limits) do
      if digest == data["binding"]["budget_digest"],
        do: :ok,
        else: Error.refusal(:analysis_budget_mismatch)
    end
  end

  defp coherence(data) do
    validated = Enum.any?(data["findings"], &(&1["concrete"] == "validated"))

    with :ok <- validity_axes(data), :ok <- execution_axes(data) do
      admission_axes(data, validated)
    end
  end

  defp validity_axes(%{"validity" => "valid"}), do: :ok
  defp validity_axes(%{"validity" => "invalid", "execution" => "error", "findings" => []}), do: :ok

  defp validity_axes(%{
         "validity" => "unsupported",
         "execution" => "unsupported",
         "findings" => []
       }),
       do: :ok

  defp validity_axes(_), do: Error.refusal(:invalid_analysis_axes)
  defp execution_axes(%{"findings" => []}), do: :ok

  defp execution_axes(%{"execution" => execution})
       when execution in ~w(completed_bounded truncated), do: :ok

  defp execution_axes(_), do: Error.refusal(:invalid_analysis_axes)
  defp admission_axes(%{"admission" => "blocked", "reason" => "counterexample"}, true), do: :ok

  defp admission_axes(%{"admission" => "inconclusive"} = data, false) do
    if not empty_completed?(data) or data["reason"] == nil,
      do: :ok,
      else: Error.refusal(:invalid_analysis_axes)
  end

  defp admission_axes(_, _), do: Error.refusal(:invalid_analysis_axes)

  defp empty_completed?(data),
    do: data["execution"] == "completed_bounded" and data["findings"] == []
end
