defmodule Mix.Tasks.Wotex.IndexTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Index

  test "takes --force only" do
    assert Index.parse_args(~w(--force)) == [force: true]
    assert Index.parse_args([]) == []
    assert_raise Mix.Error, ~r/unexpected arguments: x/, fn -> Index.parse_args(~w(x)) end
  end
end
