defmodule Mix.Tasks.Wotex.PkgTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Pkg

  test "passes every argument after the name through" do
    assert Pkg.parse_args(~w(wotex-coap test test/a_test.exs --seed 0)) ==
             {"wotex-coap", ~w(test test/a_test.exs --seed 0)}

    assert Pkg.parse_args(~w(wotex --version)) == {"wotex", ~w(--version)}
  end

  test "requires a name and a task and rejects a switch as the name" do
    assert_raise Mix.Error, ~r/usage: mix pkg NAME TASK/, fn -> Pkg.parse_args(~w(wotex)) end
    assert_raise Mix.Error, ~r/usage: mix pkg NAME TASK/, fn -> Pkg.parse_args([]) end
    assert_raise Mix.Error, ~r/usage: mix pkg NAME TASK/, fn -> Pkg.parse_args(~w(--all test)) end
  end
end
