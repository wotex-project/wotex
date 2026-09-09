defmodule Wotex.Matter.DocumentationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  doctest Wotex.Matter.Address
  doctest Wotex.Matter.TLV
end
