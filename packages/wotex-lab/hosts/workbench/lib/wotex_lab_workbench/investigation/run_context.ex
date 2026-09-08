defmodule WotexLabWorkbench.Investigation.RunContext do
  @moduledoc """
  Selects current/baseline runs inside one already-admitted browser room and
  reduces them to the bounded evidence fields an investigation may receive.
  """

  alias WotexLabWorkbench.{Run, Runs}

  @doc "Selects a run and the nearest older run of the same experiment."
  @spec select([Run.t()], String.t() | nil) :: {:ok, map(), map() | nil} | {:error, :no_run}
  def select(runs, selected_id \\ nil) when is_list(runs) do
    with {:ok, current, older} <- current_and_older(runs, selected_id) do
      baseline = Enum.find(older, &(&1.experiment == current.experiment))
      {:ok, summary(current), if(baseline, do: summary(baseline))}
    end
  end

  @doc "Returns the closed, JSON-safe evidence summary supplied to BeamLens."
  @spec summary(Run.t()) :: map()
  def summary(%Run{} = run) do
    %{
      id: run.id,
      experiment: run.experiment,
      attempt: run.attempt,
      status: run.status,
      source_mode: run.source_mode,
      backend: run.backend,
      started_at: run.started_at,
      duration_ms: run.duration_ms,
      summary: Map.new(run.summary),
      assertions: Enum.map(run.assertions, &Map.take(&1, [:id, :status, :note])),
      evidence_digest: run.record_digest,
      error: run.error
    }
    |> Runs.plain()
  end

  defp current_and_older([], _selected_id), do: {:error, :no_run}
  defp current_and_older([current | older], nil), do: {:ok, current, older}

  defp current_and_older(runs, selected_id) when is_binary(selected_id) do
    case Enum.split_while(runs, &(&1.id != selected_id)) do
      {_newer, [current | older]} -> {:ok, current, older}
      {_newer, []} -> {:error, :no_run}
    end
  end

  defp current_and_older(_runs, _selected_id), do: {:error, :no_run}
end
