defmodule Wotex.Nx.TestUnitConverter do
  @moduledoc false

  @behaviour Wotex.Nx.UnitConverter

  @impl true
  def convert(value, "degF", "Cel", _schema, :valid) when is_number(value),
    do: {:ok, (value - 32) * 5 / 9}

  def convert(_value, _from, _to, _schema, :error), do: {:error, :unsupported}
  def convert(_value, _from, _to, _schema, :invalid), do: :invalid
end
