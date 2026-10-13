defmodule Wotex.Profiles.Unit do
  @moduledoc """
  Exact supplied quantity coordinates without a built-in quantity catalogue.

  Dimensions are ordered metre, kilogram, second, ampere, kelvin, mole, candela.
  A coordinate maps to `x * scale_n / scale_d + offset_n / offset_d`.
  Construction checks canonical reduced signed-64 rationals; it grants no trust.
  """

  alias Wotex.Profiles.{Arithmetic, Error, Grammar, Limits, Numeric}

  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Revalidates a closed map or native Unit under complete caller limits."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data} = value, limits) when map_size(value) == 2, do: new(data, limits)

  def new(data, limits) do
    with {:ok, data, _} <- Grammar.admit(data, limits),
         :ok <-
           Grammar.fields(
             data,
             ~w(quantity_kind dimension scale_n scale_d offset_n offset_d),
             "/unit"
           ),
         :ok <- Grammar.id(data["quantity_kind"], "/unit/quantity_kind"),
         :ok <- dimension(data["dimension"]),
         :ok <- Numeric.rational(data, "scale_n", "scale_d", true, "/unit"),
         :ok <- Numeric.rational(data, "offset_n", "offset_d", false, "/unit") do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Returns checked coordinate data; no conversion or quantity inference occurs."
  @spec to_map(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, limits) do
    with {:ok, checked} <- new(value, limits), do: {:ok, checked.data}
  end

  @doc """
  Converts a C02 integer/decimal exactly between equal supplied quantities.

  Source and target quantity URI/dimension must both match. Reduced rational
  arithmetic refuses budget overflow or repeating fractions; no rounding,
  calibration, primitive coercion or consumer authority is inferred.
  """
  @spec convert(term(), term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def convert(value, source, target, limits) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, source} <- new(source, limits),
         {:ok, target} <- new(target, limits),
         {:ok, _, _} <-
           Grammar.admit(
             %{"source" => source.data, "target" => target.data, "value" => value},
             limits
           ),
         true <-
           source.data["quantity_kind"] == target.data["quantity_kind"] and
             source.data["dimension"] == target.data["dimension"],
         {:ok, value} <- Wotex.Runtime.Codec.Value.validate(value) do
      Arithmetic.coordinates(value, source.data, target.data, limits)
    else
      false -> Error.refusal(:unsupported_semantics, "/unit")
      {:error, %Error{}} = error -> error
      _ -> Error.refusal(:invalid_input, "/value")
    end
  end

  defp dimension(values) when is_list(values) and length(values) == 7 do
    if Enum.all?(values, &(is_integer(&1) and &1 in -32..32)),
      do: :ok,
      else: Error.refusal(:invalid_input, "/unit/dimension")
  end

  defp dimension(_), do: Error.refusal(:invalid_input, "/unit/dimension")
end
