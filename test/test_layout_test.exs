defmodule WotexWorkspace.TestLayoutTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace

  test "every module in lib/ has a test file at the matching path" do
    root = Workspace.root()

    missing =
      for source <- Path.wildcard(Path.join(root, "lib/**/*.ex")),
          relative = Path.relative_to(source, Path.join(root, "lib")),
          test_file = Path.join(["test", Path.rootname(relative) <> "_test.exs"]),
          not File.regular?(Path.join(root, test_file)),
          do: test_file

    assert missing == [], "missing test files: #{Enum.join(missing, ", ")}"
  end
end
