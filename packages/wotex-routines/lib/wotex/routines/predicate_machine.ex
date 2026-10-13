defmodule Wotex.Routines.PredicateMachine do
  @moduledoc false

  alias Wotex.Routines.{Error, Limits, Profile, Truth}

  @spec run(term(), map(), Profile.t(), Limits.t()) ::
          {:ok, boolean() | String.t()} | {:error, Error.t()}
  def run(code, values, profile, limits) when is_list(code) do
    if length(code) in 1..profile.data["predicate_nodes"] do
      case Enum.reduce_while(code, {:ok, []}, &instruction(&1, &2, values, profile, limits)) do
        {:ok, [truth]} when truth in [true, false, "unknown"] -> {:ok, truth}
        _ -> Error.refusal(:invalid_predicate_program)
      end
    else
      Error.refusal(:predicate_bound)
    end
  end

  def run(_, _, _, _), do: Error.refusal(:invalid_predicate_program)

  defp instruction(["literal", truth], {:ok, stack}, _, _, _)
       when truth in [true, false, "unknown"], do: {:cont, {:ok, [truth | stack]}}

  defp instruction([operation, binding, expected], {:ok, stack}, values, _, _)
       when operation in ~w(eq gt lt) and is_binary(binding) do
    {:cont, {:ok, [compare(operation, Map.get(values, binding, :unknown), expected) | stack]}}
  end

  defp instruction(["not"], {:ok, [truth | stack]}, _, _, _) do
    case Truth.negate(truth) do
      {:ok, value} -> {:cont, {:ok, [value | stack]}}
      _ -> {:halt, :error}
    end
  end

  defp instruction([operation, count], {:ok, stack}, _, profile, limits)
       when operation in ~w(all any) and is_integer(count) and count > 0 do
    {arguments, rest} = Enum.split(stack, count)

    with true <- length(arguments) == count,
         {:ok, value} <- Truth.combine(operation, arguments, profile, limits) do
      {:cont, {:ok, [value | rest]}}
    else
      _ -> {:halt, :error}
    end
  end

  defp instruction(_, _, _, _, _), do: {:halt, :error}

  defp compare("eq", {:known, value}, expected), do: value === expected

  defp compare("gt", {:known, value}, expected) when is_integer(value) and is_integer(expected),
    do: value > expected

  defp compare("lt", {:known, value}, expected) when is_integer(value) and is_integer(expected),
    do: value < expected

  defp compare(_, _, _), do: "unknown"
end
