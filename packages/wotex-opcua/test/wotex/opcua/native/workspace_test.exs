defmodule Wotex.OPCUA.Native.WorkspaceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Native.Workspace

  setup do
    path =
      Path.join(System.tmp_dir!(), "wotex-opcua-workspace-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(path) end)
    %{path: path}
  end

  test "WOP-X02 complete artifacts bind identity and are rehashed on read-only reuse", %{path: path} do
    identity = %{source: "fixed-source", options: ["static"], tool: "fixed-tool"}
    artifacts = ["output/client", "archives/sdk.tar.gz"]

    assert {:ok, %{reused: false, receipt: receipt}} =
             Workspace.run(path, identity, artifacts, fn ->
               File.mkdir_p!(Path.join(path, "output"))
               File.mkdir_p!(Path.join(path, "archives"))
               File.write!(Path.join(path, "output/client"), "native-artifact")
               File.write!(Path.join(path, "archives/sdk.tar.gz"), "archive-artifact")
               {:ok, %{"self_test" => true}}
             end)

    assert receipt["identity"] == %{
             "source" => "fixed-source",
             "options" => ["static"],
             "tool" => "fixed-tool"
           }

    assert map_size(receipt["artifacts"]) == 2
    before = snapshot(path)

    assert {:ok, %{reused: true, receipt: ^receipt}} =
             Workspace.run(path, identity, artifacts, fn -> flunk("reuse invoked the builder") end)

    assert snapshot(path) == before

    File.write!(Path.join(path, "output/client"), "corrupted-artifact")
    changed = snapshot(path)

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(path, identity, artifacts, fn -> flunk("invalid reuse") end)

    assert snapshot(path) == changed
  end

  test "WOP-X02 changed source/options/artifact set does not modify a completed workspace", %{
    path: path
  } do
    assert {:ok, _} =
             Workspace.run(path, %{source: "one"}, ["out"], fn ->
               File.write!(Path.join(path, "out"), "x")
               {:ok, %{}}
             end)

    before = snapshot(path)

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(path, %{source: "two"}, ["out"], fn -> :never end)

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(path, %{source: "one"}, ["out", "other"], fn -> :never end)

    assert snapshot(path) == before
  end

  test "WOP-X02 malformed inputs and an unrelated nonempty directory fail before the callback", %{
    path: path
  } do
    for {root, identity, artifacts} <- [
          {nil, %{}, ["out"]},
          {"relative", %{}, ["out"]},
          {path <> "/../escape", %{}, ["out"]},
          {path, nil, ["out"]},
          {path, %{callback: fn -> :bad end}, ["out"]},
          {path, %{}, []},
          {path, %{}, ["../out"]},
          {path, %{}, ["/out"]},
          {path, %{}, ["a//out"]},
          {path, %{}, ["out", "out"]},
          {path, %{}, [nil]},
          {path, %{}, ["wotex-native-build.json"]},
          {path, %{}, [".wotex-opcua-build.lock"]}
        ] do
      assert {:error, :invalid_build_workspace} =
               Workspace.run(root, identity, artifacts, fn -> flunk("invalid input ran") end)
    end

    refute File.exists?(path)
    assert {:error, :invalid_build_workspace} = Workspace.run(path, %{}, ["out"], nil)
    File.mkdir!(path)
    File.write!(Path.join(path, "unrelated"), "preserve")
    before = snapshot(path)

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(path, %{}, ["out"], fn -> flunk("unrelated dir ran") end)

    assert snapshot(path) == before
  end

  test "WOP-X02 failed and interrupted builds retain diagnostic files without completion", %{
    path: path
  } do
    assert {:error, :compiler_failure} =
             Workspace.run(path, %{}, ["out"], fn ->
               File.write!(Path.join(path, "build.log"), "failure")
               {:error, :compiler_failure}
             end)

    refute File.exists?(Path.join(path, "wotex-native-build.json"))
    refute File.exists?(Path.join(path, ".wotex-opcua-build.lock"))
    assert File.read!(Path.join(path, "build.log")) == "failure"

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(path, %{}, ["out"], fn -> :never end)
  end

  test "WOP-X02 exclusive workspace ownership blocks a concurrent builder", %{path: path} do
    parent = self()

    owner =
      spawn(fn ->
        Workspace.run(path, %{}, ["out"], fn ->
          send(parent, :locked)

          receive do
            :finish -> {:error, :stopped}
          end
        end)
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert_receive :locked

    assert {:error, :build_workspace_locked} =
             Workspace.run(path, %{}, ["out"], fn -> flunk("duplicate owner") end)

    monitor = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}

    assert {:error, :build_workspace_locked} =
             Workspace.run(path, %{}, ["out"], fn -> flunk("abandoned lock repaired") end)
  end

  test "WOP-X02 symlink workspaces and artifact ancestors never count as owned output", %{
    path: path
  } do
    File.mkdir!(path)
    outside = Path.join(path, "outside")
    File.mkdir!(outside)
    File.write!(Path.join(outside, "file"), "outside")
    link = Path.join(path, "link")
    File.ln_s!(outside, link)
    assert {:error, :invalid_build_workspace} = Workspace.run(link, %{}, ["out"], fn -> :never end)
    owned = Path.join(path, "owned")

    assert {:error, :invalid_build_artifact} =
             Workspace.run(owned, %{}, ["alias/file"], fn ->
               File.ln_s!(outside, Path.join(owned, "alias"))
               {:ok, %{}}
             end)

    assert File.read!(Path.join(outside, "file")) == "outside"
    assert {:error, :invalid_build_artifact} = Workspace.digest(link)
    assert {:error, :invalid_build_artifact} = Workspace.digest(nil)
  end

  test "WOP-X02 missing output, invalid callback and oversized evidence cannot create acceptance",
       %{path: path} do
    assert {:error, :invalid_build_artifact} =
             Workspace.run(path, %{}, ["out"], fn -> {:ok, %{}} end)

    assert {:error, :build_workspace_changed} =
             Workspace.run(path, %{}, ["out"], fn -> :invalid end)

    assert {:error, :invalid_build_receipt} =
             Workspace.run(path, %{}, ["out"], fn ->
               File.write!(Path.join(path, "out"), "x")
               {:ok, %{"unbounded" => String.duplicate("x", 1_048_577)}}
             end)

    refute File.exists?(Path.join(path, "wotex-native-build.json"))
  end

  test "WOP-X02 malformed, oversized and structurally forged receipts fail closed", %{path: path} do
    File.mkdir!(path)
    receipt = Path.join(path, "wotex-native-build.json")

    for bytes <- ["not-json", "[]", String.duplicate("x", 1_048_577)] do
      File.write!(receipt, bytes)

      assert {:error, :unrecognized_build_workspace} =
               Workspace.run(path, %{}, ["out"], fn -> :never end)

      assert File.read!(receipt) == bytes
    end

    for forged <- [
          %{},
          %{"format_version" => 9, "identity" => %{}, "artifacts" => %{}, "evidence" => %{}}
        ] do
      bytes = Jason.encode!(forged)
      File.write!(receipt, bytes)

      assert {:error, :build_manifest_mismatch} =
               Workspace.run(path, %{}, ["out"], fn -> :never end)

      assert File.read!(receipt) == bytes
    end
  end

  test "WOP-X02 streaming digest matches known SHA-256 across block boundaries", %{path: path} do
    File.write!(path, String.duplicate("abc", 400_000))
    expected = Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
    assert {:ok, ^expected} = Workspace.digest(path)
    assert {:error, :invalid_build_workspace} = Workspace.run(path, %{}, ["out"], fn -> :never end)
  end

  # Access time is excluded because reading the snapshot contents updates it.
  defp snapshot(path) do
    Path.wildcard(Path.join(path, "**/*"), match_dot: true)
    |> Enum.map(fn file ->
      {Path.relative_to(file, path), %{File.stat!(file) | atime: nil},
       if(File.regular?(file), do: File.read!(file), else: nil)}
    end)
  end
end
