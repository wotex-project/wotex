defmodule WotexWorkspace.PackageFilesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest

  # Hex packs only files inside a package directory, so every package keeps
  # its own copy of the licence; the copies must not drift from the root.
  test "every package ships the root LICENSE unchanged" do
    root = Workspace.root()
    license = File.read!(Path.join(root, "LICENSE"))

    drifted =
      for copy <- Path.wildcard(Path.join(root, "packages/*/LICENSE")),
          File.read!(copy) != license,
          do: Path.relative_to(copy, root)

    assert drifted == []
    assert length(Path.wildcard(Path.join(root, "packages/*/LICENSE"))) == length(packages())
  end

  defp packages, do: Map.keys(Manifest.load!().packages)
end
