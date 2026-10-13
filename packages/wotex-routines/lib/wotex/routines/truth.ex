defmodule Wotex.Routines.Truth do
  @moduledoc "Closed three-valued logic. Unknown supplies neither a false baseline nor an effect."

  alias Wotex.Routines.{Error, Limits, Profile, Validation}

  @type t :: boolean() | String.t()

  @doc "Negates a validated truth; unknown remains unknown."
  @spec negate(term()) :: {:ok, t()} | {:error, Error.t()}
  def negate(true), do: {:ok, false}
  def negate(false), do: {:ok, true}
  def negate("unknown"), do: {:ok, "unknown"}
  def negate(_), do: Error.refusal(:invalid_truth)

  @doc "Combines a finite nonempty truth array using all or any under explicit limits."
  @spec combine(term(), term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def combine(operation, values, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, values, _} <- Validation.admit(values, limits, nil),
         :ok <- Validation.choice(operation, ~w(all any), "/op"),
         :ok <- count(values, profile.data["predicate_nodes"]),
         :ok <- Validation.each(values, &Validation.choice(&1, [true, false, "unknown"], "/args")) do
      {:ok, result(operation, values)}
    end
  end

  defp count(values, maximum) when is_list(values) and values != [] and length(values) <= maximum,
    do: :ok

  defp count(_, _), do: Error.refusal(:predicate_bound, "/args")

  defp result("all", values) do
    cond do
      false in values -> false
      "unknown" in values -> "unknown"
      true -> true
    end
  end

  defp result("any", values) do
    cond do
      true in values -> true
      "unknown" in values -> "unknown"
      true -> false
    end
  end
end
