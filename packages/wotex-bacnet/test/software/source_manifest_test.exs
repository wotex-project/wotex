Code.require_file("../support/software/manifest.exs", __DIR__)
Code.require_file("../support/software/package.exs", __DIR__)

defmodule Wotex.BACnet.SourceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BACnet.{SoftwareManifest, SoftwarePackage}

  setup do
    directory =
      Path.join(System.tmp_dir!(), "wotex-bacnet-source-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "WBA-C09 WBA-V13 workspace arguments reject ambiguous and source-owned paths", c do
    root = File.cwd!()

    for arguments <- [
          [],
          [c.directory],
          ["--other", c.directory],
          ["--workspace", c.directory, "--workspace", c.directory],
          ["--workspace", "relative"],
          ["--workspace", root],
          ["--workspace", Path.join(root, "nested")],
          ["--workspace", "/tmp/invalid" <> <<0>>]
        ] do
      assert_raise Mix.Error, fn -> SoftwareManifest.arguments(arguments, root) end
    end

    link = Path.join(c.directory, "link")
    File.ln_s!(c.directory, link)

    assert_raise Mix.Error, "invalid_workspace", fn ->
      SoftwareManifest.arguments(["--workspace", link], root)
    end

    assert SoftwareManifest.arguments(["--workspace", c.directory], root) == c.directory
  end

  test "WBA-C09 WBA-V13 manifests reject missing malformed oversized and linked files", c do
    path = Path.join(c.directory, "manifest.json")
    assert_raise Mix.Error, "invalid_manifest", fn -> SoftwareManifest.read(path) end

    for bytes <- ["{", "[]", String.duplicate("x", 1_048_577)] do
      File.write!(path, bytes)
      assert_raise Mix.Error, "invalid_manifest", fn -> SoftwareManifest.read(path) end
    end

    File.rm!(path)
    source = Path.join(c.directory, "source.json")
    File.write!(source, "{}")
    File.ln_s!(source, path)
    assert_raise Mix.Error, "invalid_manifest", fn -> SoftwareManifest.read(path) end
  end

  test "WBA-C09 WBA-V13 archive members reject escape links duplicates and size overflow" do
    regular = fn name, size -> {String.to_charlist(name), :regular, size, 0, 0o600, 0, 0} end
    assert :ok = SoftwareManifest.archive_members([regular.("source/file.c", 32)])

    for entries <- [
          [],
          [:invalid],
          [regular.("../escape", 1)],
          [regular.("/escape", 1)],
          [regular.("source/../../escape", 1)],
          [regular.("source\\escape", 1)],
          [regular.("source/file", 67_108_865)],
          [{~c"link", :symlink, 0, 0, 0, 0, 0}],
          [regular.("source/file", 1), regular.("source/file", 2)],
          List.duplicate(regular.("source/file", 1), 4097)
        ] do
      assert_raise Mix.Error, "unsafe_archive", fn -> SoftwareManifest.archive_members(entries) end
    end
  end

  test "WBA-C09 WBA-V13 file checks reject links in either artifacts or parent directories", c do
    File.mkdir!(Path.join(c.directory, "context"))
    File.write!(Path.join(c.directory, "context/file"), "value")
    assert SoftwareManifest.ordinary_file?(c.directory, "context/file")
    File.ln_s!("context/file", Path.join(c.directory, "link"))
    File.ln_s!("context", Path.join(c.directory, "linked-context"))
    refute SoftwareManifest.ordinary_file?(c.directory, "link")
    refute SoftwareManifest.ordinary_file?(c.directory, "linked-context/file")
    refute SoftwareManifest.ordinary_file?(c.directory, "context/../context/file")
    refute SoftwareManifest.ordinary_file?(c.directory, "absent")
    refute SoftwareManifest.ordinary_file?(c.directory, nil)
  end

  test "WBA-C09 WBA-V13 source identities include native headers recipes and executable corpora",
       c do
    for name <- ["lib/value.ex", "test/peer.h", "test/CMakeLists.txt", "test/corpus.json"] do
      path = Path.join(c.directory, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, name)
    end

    first = SoftwareManifest.identity(c.directory)
    assert map_size(first["source_files_sha256"]) == 4
    File.write!(Path.join(c.directory, "test/peer.h"), "changed")
    refute SoftwareManifest.identity(c.directory)["source_sha256"] == first["source_sha256"]
  end

  test "WBA-C09 WBA-V13 the executed source inventory owns every download identity" do
    root = File.cwd!()
    sources = SoftwareManifest.sources(root)

    assert SoftwareManifest.pin(sources) == "3603048350b8ba543ec76cf6aa8a232b3f4d442d"

    assert SoftwareManifest.archive_sha(sources) ==
             "b5529b73551c7bea6fdd2e6e44c1e4682f1ccb017f5e3ce6d28cac87c0d26043"

    assert SoftwareManifest.source_url(sources) ==
             "https://codeload.github.com/bacnet-stack/bacnet-stack/tar.gz/" <>
               SoftwareManifest.pin(sources)

    assert SoftwarePackage.url(sources) ==
             "https://repo.hex.pm/tarballs/bacstack-0.0.1.tar"

    assert SoftwareManifest.inputs(root)["priv/fixtures/software-sources-v1.json"] ==
             sources.sha256

    descriptor = Jason.decode!(File.read!("priv/native-artifacts/software-peer.json"))

    assert "priv/fixtures/software-sources-v1.json" in descriptor["sources"]["first_party"]

    assert descriptor["sources"]["upstream"] == [
             %{
               "name" => sources.peer["name"],
               "url" => sources.peer["url"],
               "revision" => sources.peer["commit"],
               "sha256" => sources.peer["sha256"]
             }
           ]
  end

  test "WBA-C09 WBA-V13 source inventories reject stale mutable ambiguous and unknown input", c do
    valid =
      File.read!("priv/fixtures/software-sources-v1.json")
      |> Jason.decode!()

    [runtime, peer] = valid["sources"]

    invalid = [
      Map.put(valid, "status", "specified_unexecuted"),
      Map.put(valid, "unknown", true),
      Map.put(valid, "sources", [runtime, runtime]),
      Map.put(valid, "sources", [Map.put(runtime, "url", "https://example.test/latest"), peer]),
      Map.put(valid, "sources", [Map.put(runtime, "hex_outer_sha256", "short"), peer]),
      Map.put(valid, "sources", [runtime, Map.put(peer, "commit", String.upcase(peer["commit"]))]),
      Map.put(valid, "sources", [runtime, Map.put(peer, "url", peer["url"] <> "?ref=main")])
    ]

    for inventory <- invalid do
      write_inventory(c.directory, inventory)

      assert_raise Mix.Error, "invalid_source_inventory", fn ->
        SoftwareManifest.sources(c.directory)
      end
    end

    path = Path.join(c.directory, "priv/fixtures/software-sources-v1.json")
    File.rm!(path)
    File.ln_s!(File.cwd!(), path)

    assert_raise Mix.Error, "invalid_source_inventory", fn ->
      SoftwareManifest.sources(c.directory)
    end
  end

  test "WBA-C09 WBA-V13 Git identity requires one complete successful commit and tree result" do
    commit = String.duplicate("a", 40)
    tree = String.duplicate("b", 40)
    assert SoftwareManifest.git_identity({:ok, commit <> "\n" <> tree <> "\n", 0}) == {commit, tree}

    for invalid <- [
          {:ok, commit <> "\n", 0},
          {:ok, "\n", 0},
          {:ok, commit <> "\ninvalid\n", 0},
          {:ok, commit <> "\n" <> tree <> "\nextra\n", 0},
          {:ok, commit <> "\n" <> tree <> "\n", 127},
          {:error, :command_deadline, :unverified}
        ] do
      assert_raise Mix.Error, "invalid_git_identity", fn ->
        SoftwareManifest.git_identity(invalid)
      end
    end
  end

  test "WBA-C09 WBA-V13 Git package identity names the package path and its repository subtree" do
    assert SoftwareManifest.git_package({:ok, "packages/wotex-bacnet/\n", 0}) ==
             {"packages/wotex-bacnet", "HEAD:packages/wotex-bacnet/"}

    assert SoftwareManifest.git_package({:ok, "\n", 0}) == {".", "HEAD:"}

    for invalid <- [
          {:ok, "", 0},
          {:ok, "packages/wotex-bacnet\n", 0},
          {:ok, "packages/wotex-bacnet/\nextra/\n", 0},
          {:ok, "../outside/\n", 0},
          {:ok, "/absolute/\n", 0},
          {:ok, "packages/wotex-bacnet/\n", 128},
          {:error, :command_deadline, :unverified}
        ] do
      assert_raise Mix.Error, "invalid_git_identity", fn ->
        SoftwareManifest.git_package(invalid)
      end
    end
  end

  test "WBA-C09 WBA-V13 atomic receipts preserve an occupied temporary path", c do
    path = Path.join(c.directory, "result.json")
    assert :ok = SoftwareManifest.write(path, %{"status" => "failed"})
    assert SoftwareManifest.read(path) == %{"status" => "failed"}
    File.write!(path <> ".temporary", "retain")
    assert_raise File.Error, fn -> SoftwareManifest.write(path, %{"status" => "passed"}) end
    assert SoftwareManifest.read(path) == %{"status" => "failed"}
    assert File.read!(path <> ".temporary") == "retain"
  end

  test "WBA-C09 WBA-V13 package admission verifies the exact lock before decompressing", c do
    lock = Mix.Dep.Lock.read()[:bacstack]
    sources = SoftwareManifest.sources(File.cwd!())
    assert :ok = SoftwarePackage.verify_lock(lock, sources)

    for invalid <- [nil, put_elem(lock, 2, "0.0.2"), put_elem(lock, 7, "changed")] do
      assert_raise Mix.Error, "bacstack_lock_mismatch", fn ->
        SoftwarePackage.verify("invalid compressed input", invalid, c.directory, sources)
      end
    end

    for archive <- [nil, "invalid compressed input", String.duplicate("x", 1_048_577)] do
      assert_raise Mix.Error, "bacstack_archive_mismatch", fn ->
        SoftwarePackage.verify(archive, lock, c.directory, sources)
      end
    end
  end

  test "WBA-C09 WBA-V13 installed sources reject additions missing bytes and links", c do
    File.mkdir!(Path.join(c.directory, "lib"))
    source = Path.join(c.directory, "lib/value.ex")
    File.write!(source, "verified source")
    File.write!(Path.join(c.directory, ".hex"), "Hex-managed metadata")
    expected = %{"lib/value.ex" => SoftwareManifest.hash("verified source")}
    assert map_size(SoftwarePackage.verify_installed(c.directory, expected)) == 2

    File.write!(source, "changed")
    assert_installed_failure(c.directory, expected)
    File.write!(source, "verified source")
    extra = Path.join(c.directory, "lib/addition.ex")
    File.write!(extra, "additional source")
    assert_installed_failure(c.directory, expected)
    File.rm!(extra)
    File.rm!(source)
    assert_installed_failure(c.directory, expected)
    File.ln_s!(Path.join(c.directory, ".hex"), source)
    assert_installed_failure(c.directory, expected)
    File.rm!(source)
    File.write!(source, "verified source")
    File.rm!(Path.join(c.directory, ".hex"))
    assert_installed_failure(c.directory, expected)
  end

  @tag :software
  test "WBA-C09 WBA-V13 pinned archive verifies every actual installed BACstack file", c do
    workspace = System.fetch_env!("WOTEX_BACNET_SOFTWARE_WORKSPACE")
    archive = File.read!(Path.join(workspace, "bacstack.tar"))
    installed = Mix.Project.deps_paths()[:bacstack]
    lock = Mix.Dep.Lock.read()[:bacstack]
    sources = SoftwareManifest.sources(File.cwd!())
    result = SoftwarePackage.verify(archive, lock, installed, sources)
    assert result["package_file_count"] == 232
    assert map_size(result["installed_files_sha256"]) == 234

    copy = Path.join(c.directory, "bacstack")
    File.cp_r!(installed, copy)
    source = Path.join(copy, "mix.exs")
    File.write!(source, File.read!(source) <> "\n# changed dependency\n")

    assert_raise Mix.Error, "bacstack_installed_mismatch", fn ->
      SoftwarePackage.verify(archive, lock, copy, sources)
    end
  end

  defp write_inventory(root, inventory) do
    path = Path.join(root, "priv/fixtures/software-sources-v1.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(inventory))
  end

  defp assert_installed_failure(directory, expected) do
    assert_raise Mix.Error, "bacstack_installed_mismatch", fn ->
      SoftwarePackage.verify_installed(directory, expected)
    end
  end
end
