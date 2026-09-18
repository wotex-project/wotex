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

  test "git_ops.json releases every package with its tag, version and changelog" do
    config = JSON.decode!(File.read!(Path.join(Workspace.root(), "git_ops.json")))

    assert config["repository_url"] == "https://github.com/wotex-project/wotex"

    assert Enum.sort(Map.keys(config["packages"])) ==
             Enum.sort(Enum.map(packages(), &"packages/#{&1}"))

    for {_, release} <- config["packages"] do
      assert release == %{
               "exclude_paths" => ["bench"],
               "managed_files" => [%{"path" => "mix.exs", "type" => "mix"}]
             }
    end

    # No package carries its own git_ops configuration or dependency.
    for name <- packages() do
      refute File.exists?(Path.join([Workspace.root(), "packages", name, "config/config.exs"])),
             "packages/#{name}/config/config.exs"
    end
  end

  defp packages, do: Map.keys(Manifest.load!().packages)
end
