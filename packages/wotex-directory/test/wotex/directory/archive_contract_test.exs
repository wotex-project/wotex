defmodule Wotex.Directory.ArchiveContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "package inputs exclude development instructions and repository documentation" do
    files = Mix.Project.config()[:package][:files]

    for excluded <- [
          ".claude",
          ".codex",
          ".agents",
          "AGENTS.md",
          "CLAUDE.md",
          "test",
          "bin",
          "docs",
          "tasks"
        ],
        do: refute(Enum.any?(files, &(excluded in Path.split(&1))))

    for required <- ["README.md", "CHANGELOG.md", "LICENSE", "NOTICE", "lib", "mix.exs"],
        do: assert(required in files)

    assert Enum.all?(files, &File.exists?/1)
  end
end
