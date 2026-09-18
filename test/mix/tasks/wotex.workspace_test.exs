defmodule Mix.Tasks.Wotex.WorkspaceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Workspace

  test "takes --base and --all" do
    assert Workspace.parse_args(~w(--base main --all)) == [base: "main", all: true]
    assert_raise Mix.Error, fn -> Workspace.parse_args(~w(--package wotex)) end
  end

  test "runs the root checks in order" do
    assert Enum.map(Workspace.root_steps(), &elem(&1, 1)) == [
             ["compile", "--warnings-as-errors"],
             ["format", "--check-formatted"],
             ["credo", "--strict"],
             ["test"]
           ]
  end
end
