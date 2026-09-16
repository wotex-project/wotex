defmodule Wotex.Thread.NativeWorkspaceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.Native.Workspace

  setup do
    root =
      Path.join(File.cwd!(), ".wotex-thread-workspace-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WTH-B01 argument shape and absolute path are exact", %{root: root} do
    workspace = Path.join(root, "build")
    assert {:ok, ^workspace, false} = Workspace.arguments(["--workspace", workspace])
    assert {:ok, ^workspace, true} = Workspace.arguments(["--workspace", workspace, "--sanitizers"])

    for args <- [
          [],
          ["--workspace", "relative"],
          ["--workspace", "/"],
          ["--workspace", workspace, "--workspace", workspace],
          ["--workspace", workspace, "--unknown"],
          ["--workspace", Path.join(root, "../escape")]
        ] do
      assert {:error, :invalid_native_build_arguments} = Workspace.arguments(args)
    end
  end

  test "WTH-B01 completed workspace is reused read-only only after hash verification", %{
    root: root
  } do
    workspace = Path.join(root, "build")
    identity = %{"source" => "first"}
    output = Path.join(workspace, "build/wotex-thread-host")

    build = fn ->
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, "binary")
      {:ok, %{"tool" => "test"}}
    end

    assert {:ok, %{reused: false, manifest: manifest}} =
             Workspace.run(workspace, identity, ["build/wotex-thread-host"], build)

    assert manifest["schema"] == "wotex.native-build"
    assert manifest["binaries"]["build/wotex-thread-host"] == sha256("binary")

    assert {:ok, %{reused: true}} =
             Workspace.run(workspace, identity, ["build/wotex-thread-host"], fn ->
               flunk("completed workspace must not build again")
             end)

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(workspace, %{"source" => "changed"}, ["build/wotex-thread-host"], build)

    File.write!(output, "changed")

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(workspace, identity, ["build/wotex-thread-host"], build)
  end

  test "WTH-B01 unrelated, incomplete and linked workspaces do not run a builder", %{
    root: root
  } do
    builder = fn -> flunk("unsafe workspace must fail before build") end
    identity = %{"source" => "first"}
    artifact = ["build/wotex-thread-host"]
    unrelated = Path.join(root, "unrelated")
    File.mkdir_p!(unrelated)
    File.write!(Path.join(unrelated, "existing"), "keep")

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(unrelated, identity, artifact, builder)

    assert File.read!(Path.join(unrelated, "existing")) == "keep"
    File.write!(Path.join(unrelated, "native-manifest.json"), "broken")

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(unrelated, identity, artifact, builder)

    linked = Path.join(root, "linked")
    File.ln_s!(unrelated, linked)
    assert {:error, :invalid_build_workspace} = Workspace.run(linked, identity, artifact, builder)

    parent_link = Path.join(root, "parent-link")
    File.ln_s!(root, parent_link)

    assert {:error, :invalid_build_workspace} =
             Workspace.run(Path.join(parent_link, "new"), identity, artifact, builder)
  end

  test "WTH-B01 failed builds leave an incomplete workspace requiring disposal", %{root: root} do
    workspace = Path.join(root, "failed")

    assert {:error, :compile_failed} =
             Workspace.run(workspace, %{}, ["output"], fn ->
               File.write!(Path.join(workspace, "build.log"), "failure")
               {:error, :compile_failed}
             end)

    assert {:error, :build_workspace_locked} =
             Workspace.run(workspace, %{}, ["output"], fn -> flunk("unexpected reuse") end)

    assert File.exists?(Path.join(workspace, ".wotex-thread-build.lock"))
    assert File.read!(Path.join(workspace, "build.log")) == "failure"
  end

  defp sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
