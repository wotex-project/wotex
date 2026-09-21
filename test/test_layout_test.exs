defmodule WotexWorkspace.TestLayoutTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest

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

  test "every package owns and ships consumer usage rules" do
    root = Workspace.root()

    for name <- Map.keys(Manifest.load!().packages) do
      package = Path.join([root, "packages", name])
      rules = Path.join(package, "usage-rules.md")

      assert File.regular?(rules), "#{name} has no usage-rules.md"
      assert File.read!(rules) =~ ~r/\A# .+ usage rules\n/
      assert File.read!(rules) =~ "completed"
      assert File.read!(rules) =~ ~r/implementation status\s+separately/

      assert File.read!(Path.join(package, "mix.exs")) =~ "usage-rules.md",
             "#{name} does not ship usage-rules.md"
    end
  end
end
