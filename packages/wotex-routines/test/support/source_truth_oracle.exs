defmodule Wotex.Routines.SourceTruthOracle do
  @moduledoc false

  @spec evaluate(map(), map()) :: boolean() | String.t()
  def evaluate(%{"op" => "literal", "value" => value}, _), do: value

  def evaluate(%{"op" => "not", "arg" => argument}, facts) do
    case evaluate(argument, facts) do
      true -> false
      false -> true
      "unknown" -> "unknown"
    end
  end

  def evaluate(%{"op" => "all", "args" => arguments}, facts) do
    values = Enum.map(arguments, &evaluate(&1, facts))

    cond do
      false in values -> false
      "unknown" in values -> "unknown"
      true -> true
    end
  end

  def evaluate(%{"op" => "any", "args" => arguments}, facts) do
    values = Enum.map(arguments, &evaluate(&1, facts))

    cond do
      true in values -> true
      "unknown" in values -> "unknown"
      true -> false
    end
  end

  def evaluate(%{"op" => operator, "binding" => binding, "value" => expected}, facts) do
    case Map.fetch(facts, binding) do
      :error -> "unknown"
      {:ok, nil} -> "unknown"
      {:ok, actual} -> compare(operator, actual, expected)
    end
  end

  defp compare("eq", actual, expected), do: actual === expected
  defp compare("lt", actual, expected), do: actual < expected
  defp compare("gt", actual, expected), do: actual > expected
end
