defmodule Mix.Tasks.Wotex.Format.AllTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Format.All

  test "takes --check and the selection switches" do
    assert All.parse_args(~w(--check --all)) == [check: true, all: true]
  end

  test "checks formatting with --check and formats otherwise" do
    assert All.step(true) == {"format", ["format", "--check-formatted"], []}
    assert All.step(false) == {"format", ["format"], []}
  end
end
