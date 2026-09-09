defmodule Wotex.Conformance.DocumentationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  doctest Wotex.Conformance.Canonical
  doctest Wotex.Conformance.Expectation
end
