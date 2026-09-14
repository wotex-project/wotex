defmodule Wotex.Directory.ArchiveContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "package inputs exclude development instructions and allowlist individual documents" do
    files = Mix.Project.config()[:package][:files]

    for excluded <- [
          ".claude",
          ".codex",
          ".agents",
          "AGENTS.md",
          "CLAUDE.md",
          "test",
          "bin",
          "docs/tasks"
        ],
        do: refute(excluded in files)

    documents = Enum.filter(files, &String.starts_with?(&1, "docs/"))
    assert documents != []
    assert Enum.all?(documents, &File.regular?/1)
    assert "docs/specs/repository-port-evidence.md" in documents
  end
end
