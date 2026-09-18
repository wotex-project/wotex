defmodule Mix.Tasks.Wotex.Check.AllTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Check.All

  test "takes no options" do
    assert All.parse_args([]) == []
    assert_raise Mix.Error, fn -> All.parse_args(~w(--all)) end
  end
end
