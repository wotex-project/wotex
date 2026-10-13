defmodule Wotex.Profiles.Unit do
  @moduledoc """
  Exact supplied quantity coordinates without a built-in quantity catalogue.

  Dimensions are ordered metre, kilogram, second, ampere, kelvin, mole, candela.
  A coordinate maps to `x * scale_n / scale_d + offset_n / offset_d`.
  Construction checks canonical reduced signed-64 rationals; it grants no trust.
  """

  alias Wotex.Profiles.{Error, Grammar, Numeric}

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

  defp dimension(values) when is_list(values) and length(values) == 7 do
    if Enum.all?(values, &(is_integer(&1) and &1 in -32..32)),
      do: :ok,
      else: Error.refusal(:invalid_input, "/unit/dimension")
  end

  defp dimension(_), do: Error.refusal(:invalid_input, "/unit/dimension")
end
