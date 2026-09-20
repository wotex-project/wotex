defmodule Wotex.Lab.Docs.StagingTest do
  use ExUnit.Case, async: true

  alias Wotex.Lab.Docs.{SourceTree, Staging}
  alias Wotex.Lab.Test.ChildEnvironment

  test "copies committed public inputs and excludes instructions and generated trees" do
    {repository, revision, roots} = fixture_repository()
    assert {:ok, verified} = SourceTree.verify(repository, revision, roots)
    destination = temporary_path("stage")
    on_exit(fn -> File.rm_rf!(destination) end)

    source = %{
      "id" => "example",
      "revision" => revision,
      "tree_digest" => verified.tree_digest,
      "documentation_roots" => roots
    }

    File.write!(Path.join(repository, "packages/example/README.md"), "dirty working tree\n")
    assert {:ok, staged} = Staging.prepare(repository, source, destination)

    assert File.read!(Path.join(destination, "packages/example/README.md")) == "# Example\n"
    assert File.regular?(Path.join(destination, "docs/packages/example/specs/EX.01.md"))
    assert File.regular?(Path.join(destination, "packages/example/notebooks/demo.livemd"))
    refute File.exists?(Path.join(destination, "packages/example/CLAUDE.md"))
    refute File.exists?(Path.join(destination, "packages/example/bench/output.md"))
    refute File.exists?(Path.join(destination, "packages/example/native/README.md"))
    refute File.exists?(Path.join(destination, "packages/example/schema.json"))
    refute File.exists?(Path.join(destination, "packages/example/test/fixture/README.md"))
    assert staged.files == Enum.sort(staged.files)
    refute Enum.any?(staged.files, &String.ends_with?(&1, "CLAUDE.md"))
  end

  test "digest drift and occupied destinations fail without replacing bytes" do
    {repository, revision, roots} = fixture_repository()
    destination = temporary_path("occupied")
    on_exit(fn -> File.rm_rf!(destination) end)
    File.mkdir!(destination)
    marker = Path.join(destination, "marker")
    File.write!(marker, "keep")

    source = %{
      "id" => "example",
      "revision" => revision,
      "tree_digest" => "sha256:" <> String.duplicate("0", 64),
      "documentation_roots" => roots
    }

    assert {:error, {:occupied_staging_destination, ^destination}} =
             Staging.prepare(repository, source, destination)

    assert File.read!(marker) == "keep"

    fresh = temporary_path("fresh")
    on_exit(fn -> File.rm_rf!(fresh) end)

    assert {:error, {:source_tree_digest_mismatch, _}} =
             Staging.prepare(repository, source, fresh)

    refute File.exists?(fresh)
  end

  defp fixture_repository do
    root = temporary_path("repository")
    File.mkdir_p!(Path.join(root, "packages/example/notebooks"))
    File.mkdir_p!(Path.join(root, "packages/example/bench"))
    File.mkdir_p!(Path.join(root, "packages/example/native"))
    File.mkdir_p!(Path.join(root, "packages/example/test/fixture"))
    File.mkdir_p!(Path.join(root, "docs/packages/example/specs"))
    File.write!(Path.join(root, "packages/example/README.md"), "# Example\n")
    File.write!(Path.join(root, "packages/example/CLAUDE.md"), "private instructions\n")
    File.write!(Path.join(root, "packages/example/schema.json"), "{}\n")
    File.write!(Path.join(root, "packages/example/notebooks/demo.livemd"), "# Demo\n")
    File.write!(Path.join(root, "packages/example/bench/output.md"), "# Generated benchmark\n")
    File.write!(Path.join(root, "packages/example/native/README.md"), "# Internal native notes\n")
    File.write!(Path.join(root, "packages/example/test/fixture/README.md"), "# Test fixture\n")
    File.write!(Path.join(root, "docs/packages/example/specs/EX.01.md"), "# Contract\n")
    git!(root, ["init", "--quiet"])
    git!(root, ["config", "user.name", "Fixture"])
    git!(root, ["config", "user.email", "fixture@example.invalid"])
    git!(root, ["add", "."])
    git!(root, ["commit", "--quiet", "-m", "fixture"])
    on_exit(fn -> File.rm_rf!(root) end)

    revision = git!(root, ["rev-parse", "HEAD"]) |> String.trim()
    {root, revision, ["packages/example", "docs/packages/example"]}
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

  defp temporary_path(name) do
    Path.join(System.tmp_dir!(), "wotex-doc-#{name}-#{token()}")
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
