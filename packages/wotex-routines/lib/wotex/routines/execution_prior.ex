defmodule Wotex.Routines.ExecutionPrior do
  @moduledoc false

  alias Wotex.Routines.{Edge, Error, Limits, Profile, Run, Validation}

  @spec new(term(), term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def new(input, program, profile, limits) do
    with {:ok, data, _} <- Validation.admit(input, limits, nil),
         :ok <- Validation.fields(data, ~w(original busy edge)),
         {:ok, original} <- retained(data["original"], program, profile, limits),
         {:ok, busy} <- retained(data["busy"], program, profile, limits),
         {:ok, edge} <- retained_edge(data["edge"], program, profile, limits),
         :ok <- coherent(original, busy) do
      {:ok, %{"original" => original, "busy" => busy, "edge" => edge}}
    end
  end

  defp coherent(nil, _), do: :ok
  defp coherent(_, nil), do: :ok

  defp coherent(original, busy) do
    if original["original"] != busy["original"] or original == busy,
      do: :ok,
      else: Error.refusal(:conflicting_retained_original)
  end

  defp retained(nil, _, _, _), do: {:ok, nil}
  defp retained(run, program, profile, limits), do: Run.to_map(run, program, profile, limits)
  defp retained_edge(nil, _, _, _), do: {:ok, nil}

  defp retained_edge(edge, program, profile, limits),
    do: Edge.to_map(edge, program, profile, limits)
end
