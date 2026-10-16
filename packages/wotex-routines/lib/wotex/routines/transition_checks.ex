defmodule Wotex.Routines.TransitionChecks do
  @moduledoc false

  alias Wotex.Routines.Error

  @doc false
  @spec condition(boolean(), String.t()) :: :ok | {:error, Error.t()}
  def condition(true, _), do: :ok
  def condition(false, path), do: refuse(path)

  @doc false
  @spec refuse(String.t()) :: {:error, Error.t()}
  def refuse(path), do: Error.refusal(:invalid_transition, path)

  @doc false
  @spec equal(term(), term(), String.t()) :: :ok | {:error, Error.t()}
  def equal(actual, expected, path), do: condition(actual === expected, path)

  @doc false
  @spec fields(map(), map(), String.t()) :: :ok | {:error, Error.t()}
  def fields(actual, required, path),
    do: equal(Map.take(actual, Map.keys(required)), required, path)
end
