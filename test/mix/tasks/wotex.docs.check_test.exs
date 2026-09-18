defmodule Mix.Tasks.Wotex.Docs.CheckTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "takes no options" do
    assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Docs.Check.run(~w(--all)) end
  end
end
