defmodule Wotex.Nx.DocumentationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  doctest Wotex.Nx.Options
  doctest Wotex.Nx.NumericalSchema
  doctest Wotex.Nx.DataSchemaValidator
end
