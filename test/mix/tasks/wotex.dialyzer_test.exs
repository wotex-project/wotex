defmodule Mix.Tasks.Wotex.DialyzerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Dialyzer

  test "takes a name and extra arguments" do
    assert Dialyzer.parse_args(~w(wotex --format short)) == {"wotex", ~w(--format short)}
    assert_raise Mix.Error, fn -> Dialyzer.parse_args([]) end
    assert_raise Mix.Error, fn -> Dialyzer.parse_args(~w(--package wotex)) end
  end
end
