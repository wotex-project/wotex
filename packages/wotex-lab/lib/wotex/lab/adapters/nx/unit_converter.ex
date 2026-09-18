defmodule Wotex.Lab.Adapters.Nx.UnitConverter do
  @moduledoc """
  Reference temperature conversion for the exact unit strings `K` and `Cel`.

  These two conversions are explicit Lab policy. There is no general unit
  inference. The WoTEx encoder revalidates the returned value against its schema.

  The adapter subtracts 273.15 for kelvin-to-degree-Celsius conversion and adds
  273.15 for the inverse conversion. It accepts only numeric values, the exact
  unit pairs, a `Wotex.DataSchema`, and empty reference configuration. Every
  other input returns `{:error, :unsupported_conversion}`.

  This narrow implementation supports the deterministic thermal examples in
  Lab. Applications that admit further units, references, or conversion
  uncertainty should supply their own `Wotex.Nx.UnitConverter` implementation
  and record that policy with the experiment.
  """

  @behaviour Wotex.Nx.UnitConverter

  @doc "Converts a numeric temperature with empty reference configuration."
  @impl Wotex.Nx.UnitConverter
  @spec convert(term(), String.t(), String.t(), Wotex.DataSchema.t(), term()) ::
          {:ok, number()} | {:error, :unsupported_conversion}
  def convert(value, "K", "Cel", %Wotex.DataSchema{}, []) when is_number(value),
    do: {:ok, value - 273.15}

  def convert(value, "Cel", "K", %Wotex.DataSchema{}, []) when is_number(value),
    do: {:ok, value + 273.15}

  def convert(_, _, _, _, _),
    do: {:error, :unsupported_conversion}
end
