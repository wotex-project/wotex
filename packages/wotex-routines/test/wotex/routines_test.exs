defmodule Wotex.RoutinesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "reports the package version" do
    assert Wotex.Routines.version() == "0.1.0"
  end
end
