defmodule Wotex.Nx.TestUnitConverter do
  @moduledoc false

  @behaviour Wotex.Nx.UnitConverter

  @impl Wotex.Nx.UnitConverter
  def convert(value, "degF", "Cel", _, :valid) when is_number(value),
    do: {:ok, (value - 32) * 5 / 9}

  def convert(_, _, _, _, :error), do: {:error, :unsupported}
  def convert(_, _, _, _, :invalid), do: :invalid
end
