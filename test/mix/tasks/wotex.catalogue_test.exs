defmodule Mix.Tasks.Wotex.CatalogueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Catalogue

  test "takes only --check" do
    assert Catalogue.parse_args(~w(--check)) == [check: true]
    assert Catalogue.parse_args([]) == []
    assert_raise Mix.Error, fn -> Catalogue.parse_args(~w(--all)) end
  end
end
