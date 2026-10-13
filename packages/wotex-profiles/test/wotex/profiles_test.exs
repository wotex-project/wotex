defmodule Wotex.ProfilesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "reports the package version" do
    assert Wotex.Profiles.version() == "0.1.0"
  end
end
