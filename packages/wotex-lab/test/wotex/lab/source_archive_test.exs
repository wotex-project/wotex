Code.require_file("../../../bin/support/source_archive.exs", __DIR__)

defmodule Wotex.Lab.SourceArchiveTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Check.SourceArchive
  alias Wotex.Lab.Evidence.Digest

  @moduletag :tmp_dir

  test "the Workbench source archive retains executable frontend gates and their inputs", %{
    tmp_dir: root
  } do
    host = Path.expand("../../../hosts/workbench", __DIR__)
    archive = Path.join(root, "workbench.tar")
    patterns = SourceArchive.workbench_patterns()
    assert :ok = SourceArchive.create!(host, patterns, archive)
    assert {:ok, files} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    files = Map.new(files, fn {path, bytes} -> {List.to_string(path), bytes} end)

    for path <- ~w(package.json biome.jsonc .gitignore bin/register_aliases.ts .storybook/main.ts
                   tools/lint/check.ts tools/lint/frontend-style.ts tools/lint/ordering.ts
                   tools/lint/spacing.ts tools/lint/format.ts tools/lint/biome-host.ts
                   tools/lint/frontend-style.test.ts tools/lint/biome.test.ts
                   tools/lint/biome/no-classes.grit tools/lint/biome/no-object-methods.grit
                   tools/lint/biome/no-function-expressions.grit) do
      assert Map.fetch!(files, path) == File.read!(Path.join(host, path)), path
    end

    refute Enum.any?(Map.keys(files), &String.starts_with?(&1, ~w(node_modules/ _build/ deps/)))

    source = Path.join(root, "source")
    put_file(source, "tools/lint/check.ts", "original")
    assert {:ok, before} = Digest.tree(source, patterns)
    put_file(source, "tools/lint/check.ts", "changed")
    refute Digest.tree(source, patterns) == {:ok, before}
  end

  test "compressed trees use their supplied source root and preserve relative paths and bytes", %{
    tmp_dir: root
  } do
    source = Path.join(root, "site")
    put_file(source, "docs/start/index.html", "<!doctype html><title>Start</title>")
    put_file(source, ".wotex/site.etf", <<0, 1, 255>>)
    archive = Path.join(root, "site.tar.gz")
    assert :ok = SourceArchive.create!(source, ["**/*"], archive, true)
    assert {:ok, files} = :erl_tar.extract(String.to_charlist(archive), [:compressed, :memory])

    assert Map.new(files, fn {path, bytes} -> {List.to_string(path), bytes} end) == %{
             ".wotex/site.etf" => <<0, 1, 255>>,
             "docs/start/index.html" => "<!doctype html><title>Start</title>"
           }
  end

  test "empty inputs and symbolic files or parent directories refuse archive creation", %{
    tmp_dir: root
  } do
    source = Path.join(root, "source")
    File.mkdir!(source)
    archive = Path.join(root, "refused.tar")

    assert_raise RuntimeError, ~r/would be empty/, fn ->
      SourceArchive.create!(source, ["**/*"], archive)
    end

    target = Path.join(root, "target")
    put_file(target, "file.ts", "external")
    link = Path.join(source, "linked.ts")
    File.ln_s!(Path.join(target, "file.ts"), link)

    assert_raise RuntimeError, ~r/refuses symlink/, fn ->
      SourceArchive.create!(source, ["**/*"], archive)
    end

    File.rm!(link)
    File.ln_s!(target, Path.join(source, "linked"))

    assert_raise RuntimeError, ~r/refuses symlink/, fn ->
      SourceArchive.create!(source, ["linked/file.ts"], archive)
    end

    refute File.exists?(archive)
  end

  defp put_file(root, relative, bytes) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
  end
end
