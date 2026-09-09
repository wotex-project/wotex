Code.require_file("../support/software/fixture.exs", __DIR__)
Code.require_file("../support/software_other_project.ex", __DIR__)

defmodule Wotex.BACnet.BuildTaskTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Mix.Tasks.Wotex.Bacnet.Software.Build
  alias Wotex.BACnet.SoftwareManifest

  setup do
    directory =
      Path.join(System.tmp_dir!(), "wotex-bacnet-build-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "WBA-C09 WBA-V13 Mix resolves the unique task and rejects ambiguous arguments", c do
    assert Mix.Task.get("wotex.bacnet.software.build") == Build
    assert Mix.Project.config()[:aliases][:"wotex.software.build"] == "wotex.bacnet.software.build"

    for arguments <- [[], [c.directory], ["--workspace", "relative"], ["--other", c.directory]] do
      assert_raise Mix.Error, fn -> Build.run(arguments) end
    end

    assert File.ls!(c.directory) == []
  end

  test "WBA-C09 WBA-V13 another root project is rejected before acquisition" do
    Mix.Project.push(Wotex.BACnet.SoftwareOtherProject)

    try do
      assert_raise Mix.Error, "software_fixture_wrong_project", fn -> Build.run([]) end
    after
      Mix.Project.pop()
    end
  end

  test "WBA-C09 WBA-V13 installed task without checkout fixtures fails explicitly", c do
    File.cd!(c.directory, fn ->
      assert_raise Mix.Error, "software_fixture_source_required", fn -> Build.run([]) end
    end)
  end

  test "WBA-C09 WBA-V13 unrelated and incomplete workspaces remain unchanged", c do
    sentinel = Path.join(c.directory, "retain")
    File.write!(sentinel, "consumer-owned")

    assert_raise Mix.Error, "unrelated_workspace", fn ->
      Build.run(["--workspace", c.directory])
    end

    assert File.ls!(c.directory) == ["retain"]
    assert File.read!(sentinel) == "consumer-owned"
    refute File.exists?(c.directory <> ".lock")
    refute File.exists?(c.directory <> ".bootstrap.lock")

    File.write!(Path.join(c.directory, "peer-manifest.json"), "{}")

    assert_raise Mix.Error, "manifest_mismatch", fn ->
      Build.run(["--workspace", c.directory])
    end

    assert File.read!(sentinel) == "consumer-owned"
    refute File.exists?(c.directory <> ".lock")
  end

  @tag :software
  test "WBA-C09 WBA-V13 native manifest reuses exact peers and detects modified artifacts", c do
    workspace = copy_workspace(c.directory)
    manifest = SoftwareManifest.read(Path.join(workspace, "peer-manifest.json"))
    assert :ok = Build.run(["--workspace", workspace])
    assert SoftwareManifest.read(Path.join(workspace, "peer-manifest.json")) == manifest

    for binary <- ["/normal/wotex-bacnet-peer", "/sanitizer/wotex-bacnet-peer"] do
      assert manifest["native"]["versions"][binary] == "wotex-bacnet-peer 1 bacnet-stack 1.7.0-rc4"
      assert byte_size(manifest["native"]["binary_hashes"][binary]) == 64
    end

    assert manifest["runtime_dependency"]["package_file_count"] == 232
    assert manifest["native"]["metadata"]["packages.txt"] =~ "libc6"

    manifest_path = Path.join(workspace, "peer-manifest.json")
    SoftwareManifest.write(manifest_path, Map.put(manifest, "build_options", %{}))

    assert_raise Mix.Error, "build_options_mismatch", fn ->
      Build.run(["--workspace", workspace])
    end

    SoftwareManifest.write(manifest_path, manifest)
    guardian = Path.join(workspace, "command")
    File.write!(guardian, "changed")

    assert_raise Mix.Error, "artifact_hash_mismatch", fn ->
      Build.run(["--workspace", workspace])
    end

    assert File.read!(workspace <> ".lock") == ""
  end

  @tag :software
  test "WBA-C09 WBA-V13 artifact parents and downloaded sources cannot be substituted", c do
    workspace = copy_workspace(c.directory)
    archive = Path.join(workspace, "source.tar.gz")
    bytes = File.read!(archive)
    File.write!(archive, "changed")

    assert_raise Mix.Error, "archive_hash_mismatch", fn ->
      Build.run(["--workspace", workspace])
    end

    File.write!(archive, bytes)
    context = Path.join(workspace, "context")
    moved = Path.join(c.directory, "original-context")
    File.rename!(context, moved)
    File.ln_s!(moved, context)

    assert_raise Mix.Error, "artifact_hash_mismatch", fn ->
      Build.run(["--workspace", workspace])
    end

    assert File.dir?(moved)
    refute File.exists?(workspace <> ".lock")
  end

  defp copy_workspace(directory) do
    source = System.fetch_env!("WOTEX_BACNET_SOFTWARE_WORKSPACE")
    manifest = SoftwareManifest.read(Path.join(source, "peer-manifest.json"))
    workspace = Path.join(directory, "workspace")
    File.mkdir!(workspace)

    for name <- ["peer-manifest.json" | Map.keys(manifest["files"])] do
      target = Path.join(workspace, name)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(Path.join(source, name), target)
    end

    on_exit(fn -> File.rm(workspace <> ".lock") end)
    workspace
  end
end
