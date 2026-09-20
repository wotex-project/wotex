defmodule Wotex.Lab.Docs.SourceTreeTest do
  use ExUnit.Case, async: true

  alias Wotex.Lab.Docs.{Admission, SourceTree}
  alias Wotex.Lab.Test.ChildEnvironment

  test "binds exact recursive Git records and ignores working-tree changes" do
    repository = fixture_repository()
    revision = git!(repository, ["rev-parse", "HEAD"]) |> String.trim()
    roots = ["packages/example", "docs/packages/example"]

    assert {:ok, first} = SourceTree.verify(repository, revision, roots)
    assert first.tree_digest =~ ~r/\Asha256:[0-9a-f]{64}\z/
    assert first.files == Enum.sort(first.files)
    assert "packages/example/README.md" in first.files

    File.write!(Path.join(repository, "packages/example/README.md"), "uncommitted\n")
    assert {:ok, second} = SourceTree.verify(repository, revision, roots)
    assert second == first

    File.write!(Path.join(repository, "packages/example/README.md"), "committed change\n")
    git!(repository, ["add", "packages/example/README.md"])
    git!(repository, ["commit", "-m", "change fixture"])
    changed_revision = git!(repository, ["rev-parse", "HEAD"]) |> String.trim()

    assert {:ok, changed} = SourceTree.verify(repository, changed_revision, roots)
    refute changed.tree_digest == first.tree_digest
  end

  test "rejects missing roots, mutable revisions, symlinks and digest drift" do
    repository = fixture_repository()
    revision = git!(repository, ["rev-parse", "HEAD"]) |> String.trim()
    roots = ["packages/example", "docs/packages/example"]

    assert {:error, {:invalid_source_revision, "main"}} =
             SourceTree.verify(repository, "main", roots)

    assert {:error, {:missing_documentation_root, "missing", _, _}} =
             SourceTree.verify(repository, revision, ["missing"])

    assert {:ok, source} = SourceTree.verify(repository, revision, roots)

    assert {:error, {:source_tree_digest_mismatch, _}} =
             SourceTree.verify_digest(
               repository,
               revision,
               roots,
               "sha256:" <> String.duplicate("0", 64)
             )

    assert {:ok, ^source} =
             SourceTree.verify_digest(repository, revision, roots, source.tree_digest)

    File.ln_s!("README.md", Path.join(repository, "packages/example/link.md"))
    git!(repository, ["add", "packages/example/link.md"])
    git!(repository, ["commit", "-m", "add fixture link"])
    link_revision = git!(repository, ["rev-parse", "HEAD"]) |> String.trim()

    assert {:error, {:symlinked_documentation_source, "packages/example/link.md"}} =
             SourceTree.verify(repository, link_revision, roots)
  end

  test "public admission is closed before source bytes are parsed" do
    roots = ["packages/example", "docs/packages/example"]

    assert Admission.public?("packages/example/README.md", roots)
    assert Admission.public?("packages/example/notebooks/demo.livemd", roots)
    assert Admission.public?("docs/packages/example/specs/EX.01.md", roots)
    refute Admission.public?("packages/example/CLAUDE.md", roots)
    refute Admission.public?("packages/example/deps/copied.md", roots)
    refute Admission.public?("packages/example/credentials.md", roots)
    refute Admission.public?("docs/tasks/local/tracker.md", ["docs"])
    refute Admission.public?("packages/other/README.md", roots)
    refute Admission.public?("packages/example/schema.json", roots)
  end

  defp fixture_repository do
    root = Path.join(System.tmp_dir!(), "wotex-doc-source-tree-#{token()}")

    File.mkdir_p!(Path.join(root, "packages/example"))
    File.mkdir_p!(Path.join(root, "docs/packages/example/specs"))
    File.write!(Path.join(root, "packages/example/README.md"), "# Example\n")
    File.write!(Path.join(root, "packages/example/CLAUDE.md"), "private instructions\n")
    File.write!(Path.join(root, "docs/packages/example/specs/EX.01.md"), "# Contract\n")
    git!(root, ["init", "--quiet"])
    git!(root, ["config", "user.name", "Fixture"])
    git!(root, ["config", "user.email", "fixture@example.invalid"])
    git!(root, ["add", "."])
    git!(root, ["commit", "--quiet", "-m", "fixture"])
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp git!(repository, args) do
    case System.cmd("git", ["-C", repository | args],
           stderr_to_stdout: true,
           env: ChildEnvironment.scrubbed()
         ) do
      {output, 0} -> output
      {output, status} -> flunk("git failed with #{status}: #{output}")
    end
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
