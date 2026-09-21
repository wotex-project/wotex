defmodule Wotex.Workspace.NativeArtifact.ArchiveTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.Archive
  alias WotexWorkspace.Fixtures
  alias WotexWorkspace.NativeArtifactArchiveFixture, as: Tar

  setup context do
    root = Fixtures.tmp_dir(context)
    %{root: root, archive: Path.join(root, "artifact.tar")}
  end

  test "scans plain and gzip archives without extracting", context do
    entries = [manifest("{}"), file("bin/tool", "payload")]

    for {name, gzip?} <- [{"artifact.tar", false}, {"artifact.tar.gz", true}] do
      path = Tar.write!(Path.join(context.root, name), entries, gzip: gzip?)
      assert {:ok, scan} = Archive.scan(path)
      assert scan.manifest_bytes == "{}"
      assert [%{"path" => "bin/tool", "sha256" => digest}] = scan.entries
      assert digest == sha256("payload")
      refute File.exists?(Path.join(context.root, "bin"))
    end
  end

  test "rejects path traversal, absolute, invalid, duplicate and over-deep names", context do
    cases = [
      {"absolute", [%{file("/etc/passwd", "x") | path: "/etc/passwd"}], "normalized relative"},
      {"dot", [file("bin/./tool", "x")], "normalized relative"},
      {"parent", [file("bin/../tool", "x")], "normalized relative"},
      {"invalid", [file(<<255>>, "x")], "valid UTF-8"},
      {"duplicate", [file("bin/tool", "x"), file("bin/tool", "y")], "repeats normalized path"},
      {"depth", [file("a/b/c", "x")], "nesting depth"}
    ]

    for {name, entries, expected} <- cases do
      path = Tar.write!(Path.join(context.root, name <> ".tar"), [manifest("{}") | entries])
      limits = if name == "depth", do: %Archive.Limits{path_depth: 2}, else: %Archive.Limits{}
      assert {:error, message} = Archive.scan(path, limits), name
      assert message =~ expected, name
    end
  end

  test "rejects escaping links, hard links, special files and prohibited permissions", context do
    cases = [
      {"symlink", [%{path: "bin/link", kind: :symlink, link_target: "../../etc", mode: 0o755}],
       "escapes"},
      {"hardlink", [%{path: "bin/link", kind: :hardlink, link_target: "../../etc"}], "escapes"},
      {"device", [%{path: "bin/device", type: ?3}], "device nodes"},
      {"fifo", [%{path: "bin/fifo", type: ?6}], "FIFOs"},
      {"socket", [%{path: "bin/socket", type: ?s}], "unsupported"},
      {"setuid", [file("bin/tool", "x", mode: 0o4755)], "set-user-ID"},
      {"world", [file("bin/tool", "x", mode: 0o777)], "world-writable"}
    ]

    for {name, entries, expected} <- cases do
      path = Tar.write!(Path.join(context.root, name <> ".tar"), [manifest("{}") | entries])
      assert {:error, message} = Archive.scan(path), name
      assert message =~ expected, name
    end
  end

  test "enforces compressed, expanded, ratio, entry, file, path and manifest bounds", context do
    entries = [manifest(String.duplicate("m", 64)), file("bin/tool", String.duplicate("x", 2_048))]
    plain = Tar.write!(context.archive, entries)
    gzip = Tar.write!(Path.join(context.root, "artifact.tar.gz"), entries, gzip: true)
    size = File.stat!(plain).size

    assert {:error, message} = Archive.scan(plain, %Archive.Limits{compressed_bytes: size - 1})
    assert message =~ "compressed bytes"

    assert {:error, message} = Archive.scan(plain, %Archive.Limits{expanded_bytes: 512})
    assert message =~ "expanded bytes"

    assert {:error, message} = Archive.scan(gzip, %Archive.Limits{expansion_ratio: 1})
    assert message =~ "expansion ratio"

    assert {:error, message} = Archive.scan(plain, %Archive.Limits{entries: 1})
    assert message =~ "entries"

    assert {:error, message} = Archive.scan(plain, %Archive.Limits{file_bytes: 1_000})
    assert message =~ "file exceeds"

    assert {:error, message} = Archive.scan(plain, %Archive.Limits{path_bytes: 4})
    assert message =~ "path exceeds"

    assert {:error, message} = Archive.scan(plain, %Archive.Limits{manifest_bytes: 16})
    assert message =~ "manifest exceeds"

    assert {:error, message} = Archive.scan(plain, %Archive.Limits{entries: 0})
    assert message =~ "positive integers"
  end

  test "rejects corrupt headers, missing end records and interrupted gzip", context do
    bytes = Tar.bytes([manifest("{}")])
    File.write!(context.archive, Tar.corrupt_checksum(bytes))
    assert {:error, message} = Archive.scan(context.archive)
    assert message =~ "checksum mismatch"

    Tar.write!(context.archive, [manifest("{}")], truncate: 1_024)
    assert {:error, message} = Archive.scan(context.archive)
    assert message =~ "ended during"

    gzip = Tar.bytes([manifest("{}")], gzip: true)
    File.write!(context.archive, binary_part(gzip, 0, byte_size(gzip) - 4))
    assert {:error, message} = Archive.scan(context.archive)
    assert message =~ "gzip"
  end

  defp manifest(content), do: file(Archive.manifest_path(), content)

  defp file(path, content, opts \\ []) do
    %{path: path, kind: :file, content: content, mode: Keyword.get(opts, :mode, 0o644)}
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
