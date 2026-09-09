defmodule WotexContinuum.DocumentationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  doctest WotexContinuum.Contract
  doctest WotexContinuum.Validation
end
