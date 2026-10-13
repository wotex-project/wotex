defmodule Wotex.Routines.Unit do
  @moduledoc "Exact affine integer units with explicit dimensions and domains; conversion never rounds."

  alias Wotex.Routines.{Error, Limits, Validation}

  @dimensions ~w(temperature fraction illuminance power energy time electric_potential)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Validates a closed dimension, bounded coefficients and integer domain."
  @spec new(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <-
           Validation.fields(data, ~w(dimension name scale_n scale_d offset_n offset_d min max)),
         :ok <- Validation.choice(data["dimension"], @dimensions, "/dimension"),
         :ok <- Validation.text(data["name"], "/name"),
         :ok <-
           Validation.each(~w(scale_n scale_d offset_d), fn key ->
             Validation.integer(data[key], limits, "/" <> key, 1)
           end),
         :ok <-
           Validation.each(~w(offset_n min max), fn key ->
             Validation.integer(data[key], limits, "/" <> key)
           end),
         :ok <- domain_order(data) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Converts an integer exactly, refusing dimension mismatch, inexactness and overflow."
  @spec convert(term(), t(), t(), Limits.t()) :: {:ok, integer()} | {:error, Error.t()}
  def convert(value, from, to, limits) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, from} <- new(from, limits),
         {:ok, to} <- new(to, limits),
         :ok <- Validation.integer(value, limits, "/value"),
         :ok <- same_dimension(from.data, to.data),
         :ok <- in_domain(value, from.data) do
      a = from.data
      b = to.data
      n = value * a["scale_n"] * a["offset_d"] + a["offset_n"] * a["scale_d"]
      d = a["scale_d"] * a["offset_d"]
      numerator = (n * b["offset_d"] - b["offset_n"] * d) * b["scale_d"]
      denominator = d * b["offset_d"] * b["scale_n"]
      exact_result(numerator, denominator, b, limits)
    end
  end

  @doc "Revalidates a unit before projecting the closed JSON representation."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, limits) do
    with {:ok, value} <- new(value, limits), do: {:ok, value.data}
  end

  defp exact_result(n, d, unit, limits) do
    if rem(n, d) == 0 do
      result = div(n, d)

      with :ok <- Validation.integer(result, limits, "/value"),
           :ok <- in_domain(result, unit) do
        {:ok, result}
      end
    else
      Error.refusal(:inexact_conversion, "/value")
    end
  end

  defp same_dimension(%{"dimension" => dimension}, %{"dimension" => dimension}), do: :ok
  defp same_dimension(_, _), do: Error.refusal(:incompatible_dimension, "/dimension")

  defp in_domain(value, %{"min" => low, "max" => high}) do
    if value >= low and value <= high, do: :ok, else: Error.refusal(:out_of_domain, "/value")
  end

  defp domain_order(%{"min" => low, "max" => high}) do
    if low <= high, do: :ok, else: Error.refusal(:out_of_domain, "/min")
  end
end
