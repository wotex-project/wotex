defmodule Mix.Tasks.Wotex.Native.AdvisoriesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Advisories

  test "takes --offline only" do
    assert Advisories.parse_args(~w(--offline)) == [offline: true]
    assert Advisories.parse_args([]) == []
    assert_raise Mix.Error, fn -> Advisories.parse_args(~w(--all)) end
  end
end
