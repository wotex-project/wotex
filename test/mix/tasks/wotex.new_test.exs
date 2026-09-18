defmodule Mix.Tasks.Wotex.NewTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.New

  test "takes a name and an optional dependency list" do
    assert New.parse_args(~w(wotex-demo)) == {"wotex-demo", depends_on: ["wotex"]}

    assert New.parse_args(~w(wotex-demo --depends-on wotex,wotex-runtime)) ==
             {"wotex-demo", depends_on: ["wotex", "wotex-runtime"]}

    assert_raise Mix.Error, ~r/usage: mix wotex.new NAME/, fn -> New.parse_args([]) end
    assert_raise Mix.Error, fn -> New.parse_args(~w(a b)) end
  end
end
