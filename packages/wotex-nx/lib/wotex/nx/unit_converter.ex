defmodule Wotex.Nx.UnitConverter do
  @moduledoc "Port for explicit, consumer-supplied unit conversion."

  alias Wotex.DataSchema

  @callback convert(term(), String.t(), String.t(), DataSchema.t(), term()) ::
              {:ok, term()} | {:error, term()}
end
