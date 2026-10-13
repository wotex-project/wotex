defmodule Wotex.Routines.AnalysisExecution do
  @moduledoc false

  alias Wotex.Routines.{AnalysisResult, Error, Validation}

  @states MapSet.new(["state(fresh,0)", "state(proposed,1)", "state(cancelled,1)"])

  @doc false
  @spec run(map(), String.t(), integer(), (binary(), map(), keyword() -> term())) ::
          {:ok, AnalysisResult.t()} | {:error, Error.t()}
  def run(prepared, path, deadline, search) do
    selection = prepared.request["effective_limits"]

    outcome =
      cond do
        expired?(deadline) -> {:timeout, "budget_exhausted"}
        not fits?(prepared.model, selection) -> {:truncated, "budget_exhausted"}
        true -> execute(prepared, path, deadline, search)
      end

    finish(prepared, outcome, deadline)
  end

  defp fits?(model, selection) do
    selection["max_states"] >= 3 and selection["max_transitions"] >= 5 and
      selection["max_depth"] >= 2 and
      byte_size(model["model_bytes"]) <= selection["max_model_bytes"]
  end

  defp execute(prepared, path, deadline, search) do
    with {:ok, states} <- query(prepared, path, deadline, search, "state(fresh, 0)", "S:State"),
         :ok <- states(states),
         {:ok, literal} <- query(prepared, path, deadline, search, "requested", "B:Bool"),
         :ok <- literal(literal, prepared.model) do
      {:completed_bounded, nil}
    else
      {:error, {execution, reason}} -> {execution, reason}
    end
  end

  defp query(prepared, path, deadline, search, initial, pattern) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, {:timeout, "budget_exhausted"}}
    else
      query = %{
        module: "ROUTINE-PROPOSAL-PREFIX",
        initial: initial,
        pattern: pattern,
        max_depth: 2,
        max_solutions: 4
      }

      options = [
        maude_path: path,
        deadline_ms: deadline,
        timeout: remaining,
        max_response_bytes: prepared.request["effective_limits"]["max_output_bytes"]
      ]

      receipt(search.(prepared.model["model_bytes"], query, options), prepared, deadline)
    end
  end

  defp receipt(result, prepared, deadline) do
    cond do
      expired?(deadline) -> {:error, {:timeout, "budget_exhausted"}}
      result == {:error, :unavailable} -> {:error, {:unavailable, "backend_unavailable"}}
      true -> checked_receipt(result, prepared)
    end
  end

  defp checked_receipt({:ok, receipt}, prepared) when is_map(receipt) do
    if identity?(receipt, prepared) do
      completion(receipt)
    else
      {:error, {:error, "correspondence_failed"}}
    end
  end

  defp checked_receipt({:error, %{type: :timeout}}, _),
    do: {:error, {:timeout, "budget_exhausted"}}

  defp checked_receipt({:error, %{type: :load_error}}, _),
    do: {:error, {:unavailable, "backend_unavailable"}}

  defp checked_receipt(_, _), do: {:error, {:error, "incomplete"}}

  defp identity?(receipt, prepared) do
    runtime = prepared.request["runtime"]

    receipt[:model_digest] == prepared.model["model_digest"] and
      receipt[:executable_digest] == runtime["executable_digest"] and
      receipt[:executable_version] == runtime["executable_version"] and
      receipt[:parser_version] == runtime["parser_version"] and receipt[:backend] == :port
  end

  defp completion(
         %{termination: :completed_declared_bound, error: nil, solutions: solutions} = receipt
       )
       when is_list(solutions), do: {:ok, receipt}

  defp completion(%{termination: termination})
       when termination in [:depth_truncation, :solution_limit, :output_truncation],
       do: {:error, {:truncated, "budget_exhausted"}}

  defp completion(%{termination: :timeout}), do: {:error, {:timeout, "budget_exhausted"}}
  defp completion(_), do: {:error, {:error, "incomplete"}}

  defp states(%{solutions: solutions}) do
    values = Enum.map(solutions, &substitution(&1, "S:State"))

    if length(values) == 3 and MapSet.new(values) == @states,
      do: :ok,
      else: {:error, {:error, "correspondence_failed"}}
  end

  defp literal(%{solutions: [solution]}, model) do
    expected = to_string(model["program"]["ir"]["steps"]["input"])

    if substitution(solution, "B:Bool") == expected,
      do: :ok,
      else: {:error, {:error, "correspondence_failed"}}
  end

  defp literal(_, _), do: {:error, {:error, "correspondence_failed"}}

  defp substitution(%{substitution: values}, key) when is_map(values) do
    case values[key] do
      value when is_binary(value) -> String.replace(value, ~r/\s+/, "")
      _ -> nil
    end
  end

  defp substitution(_, _), do: nil

  defp finish(prepared, outcome, deadline) do
    {execution, reason} = if expired?(deadline), do: {:timeout, "budget_exhausted"}, else: outcome
    complete = execution == :completed_bounded

    result = %{
      "format" => "wotex.routines.analysis.result@1",
      "binding" => prepared.binding,
      "effective_limits" => prepared.request["effective_limits"],
      "validity" => "valid",
      "findings" => [],
      "execution" => Atom.to_string(execution),
      "admission" => "inconclusive",
      "reason" => reason,
      "counts" => %{"states" => if(complete, do: 3), "transitions" => if(complete, do: 5)}
    }

    with {:ok, checked} <- AnalysisResult.new(result, prepared.limits),
         {:ok, bytes} <- Wotex.JSON.encode(result, Validation.json_options(prepared.limits.data)),
         true <- byte_size(bytes) <= prepared.request["effective_limits"]["max_output_bytes"] do
      if expired?(deadline) and execution != :timeout,
        do: finish(prepared, {:timeout, "budget_exhausted"}, deadline),
        else: {:ok, checked}
    else
      false -> Error.refusal(:analysis_output_bound)
      error -> error
    end
  end

  defp expired?(deadline), do: deadline <= System.monotonic_time(:millisecond)
end
