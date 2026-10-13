defmodule Wotex.Profiles.Definitions do
  @moduledoc "Bounded explicitly supplied descriptors, without discovering or scanning a catalogue."

  alias Wotex.Profiles.{Definition, Error, Grammar, Limits}

  @doc "Revalidates and sorts descriptors by id/version; duplicate identities always refuse."
  @spec new(term(), term()) :: {:ok, [Definition.t()]} | {:error, Error.t()}
  def new(values, limits) when is_list(values) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, data} <- data(values, limits.data["max_definitions"], []),
         {:ok, _, _} <- Grammar.admit(data, limits),
         {:ok, checked} <- definitions(values, limits),
         checked = Enum.sort_by(checked, &{&1.data["id"], &1.data["version"]}),
         :ok <- Grammar.sorted_unique(checked, &{&1.data["id"], &1.data["version"]}, "/definitions") do
      {:ok, checked}
    else
      error -> error
    end
  end

  def new(_, _), do: Error.refusal(:invalid_input, "/definitions")

  defp data([], _, acc), do: {:ok, Enum.reverse(acc)}
  defp data([_ | _], 0, _), do: Error.refusal(:input_limit, "/definitions")

  defp data([%Definition{data: value} | rest], remaining, acc),
    do: data(rest, remaining - 1, [value | acc])

  defp data([value | rest], remaining, acc), do: data(rest, remaining - 1, [value | acc])
  defp data(_, _, _), do: Error.refusal(:invalid_input, "/definitions")

  defp definitions(values, limits) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, checked} ->
      case Definition.new(value, limits) do
        {:ok, value} -> {:cont, {:ok, [value | checked]}}
        error -> {:halt, error}
      end
    end)
  end
end
