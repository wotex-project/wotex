defmodule Wotex.Lab.Adapters.Nx.UnitConverter do
  @moduledoc """
  Reference temperature conversion for the exact unit strings `K` and `Cel`.

  These two conversions are explicit Lab policy. There is no general unit
  inference. The WoTEx encoder revalidates the returned value against its schema.
  """

  @behaviour Wotex.Nx.UnitConverter

  @doc "Converts a numeric temperature with empty reference configuration."
  @impl true
  @spec convert(term(), String.t(), String.t(), Wotex.DataSchema.t(), term()) ::
          {:ok, number()} | {:error, :unsupported_conversion}
  def convert(value, "K", "Cel", %Wotex.DataSchema{}, []) when is_number(value),
    do: {:ok, value - 273.15}

  def convert(value, "Cel", "K", %Wotex.DataSchema{}, []) when is_number(value),
    do: {:ok, value + 273.15}

  def convert(_value, _source, _target, _schema, _config),
    do: {:error, :unsupported_conversion}
end
