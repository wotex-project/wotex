defmodule Wotex.CoAP.Native.WorkspaceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.CoAP.{Native.Workspace, NativeBackend}

  @revision "7cf7465b784baded4de183290c547d582becfd28"

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-native-workspace-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WCO-N01 publishes a runtime-usable manifest and reuses it read-only", %{root: root} do
    artifacts = ["bin/wotex-coap-oscore", "lib/libcoap-3.a", "logs/build.log"]
    identity = %{"source" => @revision, "options" => ["static", "oscore"]}

    assert {:ok, %{reused: false, manifest: manifest}} =
             Workspace.run(root, identity, artifacts, fn -> build_fixture(root) end)

    assert manifest["schema"] == "wotex.coap.native@1"
    assert manifest["workspace"]["identity"] == identity
    assert Map.keys(manifest["workspace"]["artifacts"]) |> Enum.sort() == artifacts
    refute File.exists?(Path.join(root, ".native-manifest.json.pending"))
    refute File.exists?(Path.join(root, ".wotex-coap-build.lock"))

    executable = Path.join(root, "bin/wotex-coap-oscore")
    manifest_path = Path.join(root, "native-manifest.json")
    assert {:ok, backend} = NativeBackend.verify(%{executable: executable, manifest: manifest_path})
    assert backend.sha256 == manifest["executables"]["wotex-coap-oscore"]["sha256"]

    before = snapshot(root)

    assert {:ok, %{reused: true, manifest: ^manifest}} =
             Workspace.run(root, identity, artifacts, fn -> flunk("reuse invoked builder") end)

    assert snapshot(root) == before
  end

  test "WCO-N01 changed inputs, artifacts and unrelated content fail without mutation", %{
    root: root
  } do
    artifacts = ["bin/wotex-coap-oscore", "lib/libcoap-3.a", "logs/build.log"]
    identity = %{"source" => @revision}
    assert {:ok, _} = Workspace.run(root, identity, artifacts, fn -> build_fixture(root) end)

    before = snapshot(root)

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(root, %{"source" => "changed"}, artifacts, fn -> :never end)

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(root, identity, Enum.drop(artifacts, -1), fn -> :never end)

    assert snapshot(root) == before

    File.write!(Path.join(root, "bin/wotex-coap-oscore"), "changed")
    changed = snapshot(root)

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(root, identity, artifacts, fn -> :never end)

    assert snapshot(root) == changed

    File.write!(Path.join(root, "unrelated"), "preserve")
    unrelated = snapshot(root)

    assert {:error, :build_manifest_mismatch} =
             Workspace.run(root, identity, artifacts, fn -> :never end)

    assert snapshot(root) == unrelated
  end

  test "WCO-N01 rejects malformed admission and unrelated directories before building", %{
    root: root
  } do
    overlong = "/" <> String.duplicate("a", 4_096)

    for {path, identity, artifacts} <- [
          {nil, %{}, ["out"]},
          {"relative", %{}, ["out"]},
          {root <> "/../escape", %{}, ["out"]},
          {root <> <<0>>, %{}, ["out"]},
          {overlong, %{}, ["out"]},
          {root, nil, ["out"]},
          {root, %{bad: self()}, ["out"]},
          {root, %{}, []},
          {root, %{}, ["out", "out"]},
          {root, %{}, ["../out"]},
          {root, %{}, ["/out"]},
          {root, %{}, ["a//out"]},
          {root, %{}, ["a\\out"]},
          {root, %{}, ["native-manifest.json"]},
          {root, %{}, [nil]}
        ] do
      assert {:error, :invalid_build_workspace} =
               Workspace.run(path, identity, artifacts, fn -> flunk("invalid build ran") end)
    end

    refute File.exists?(root)
    assert {:error, :invalid_build_workspace} = Workspace.run(root, %{}, ["out"], nil)
    File.mkdir!(root)
    File.write!(Path.join(root, "unrelated"), "preserve")
    before = snapshot(root)

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(root, %{}, ["out"], fn -> flunk("unrelated build ran") end)

    assert snapshot(root) == before
  end

  test "WCO-N01 incomplete builds retain diagnostics without becoming reusable", %{root: root} do
    assert {:error, :compiler_failed} =
             Workspace.run(root, %{}, ["bin/result"], fn ->
               File.write!(Path.join(root, "compiler.log"), "failure")
               {:error, :compiler_failed}
             end)

    refute File.exists?(Path.join(root, "native-manifest.json"))
    refute File.exists?(Path.join(root, ".wotex-coap-build.lock"))
    assert File.read!(Path.join(root, "compiler.log")) == "failure"

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(root, %{}, ["bin/result"], fn -> :never end)
  end

  test "WCO-N01 admits a pre-existing empty root and nested artifact directories", %{root: root} do
    File.mkdir!(root)
    artifact = "one/two/result"

    assert {:ok, %{reused: false}} =
             Workspace.run(root, %{}, [artifact], fn ->
               path = Path.join(root, artifact)
               File.mkdir_p!(Path.dirname(path))
               File.write!(path, "nested")
               {:ok, base_manifest(digest(path))}
             end)
  end

  test "WCO-N01 normalizes filesystem failures and unreadable artifacts", %{root: root} do
    assert {:error, :build_workspace_unavailable} =
             Workspace.run(root, %{}, ["out"], fn ->
               raise File.Error, action: "write", path: root, reason: :eacces
             end)

    File.rm_rf!(root)

    assert {:error, :invalid_build_artifact} =
             Workspace.run(root, %{}, ["out"], fn ->
               path = Path.join(root, "out")
               File.write!(path, "unreadable")
               File.chmod!(path, 0o000)
               {:ok, base_manifest("unused")}
             end)
  end

  test "WCO-N01 rejects missing, extra-directory and invalid manifest output", %{root: root} do
    assert {:error, :invalid_build_artifact} =
             Workspace.run(root, %{}, ["bin/result"], fn -> {:ok, base_manifest("missing")} end)

    File.rm_rf!(root)

    assert {:error, :invalid_build_artifact} =
             Workspace.run(root, %{}, ["bin/result"], fn ->
               File.mkdir_p!(Path.join(root, "bin"))
               File.mkdir_p!(Path.join(root, "extra"))
               File.write!(Path.join(root, "bin/result"), "result")
               {:ok, base_manifest(digest(Path.join(root, "bin/result")))}
             end)

    File.rm_rf!(root)

    assert {:error, :build_workspace_changed} =
             Workspace.run(root, %{}, ["out"], fn -> :invalid end)

    File.rm_rf!(root)

    assert {:error, :invalid_build_manifest} =
             Workspace.run(root, %{}, ["out"], fn ->
               File.write!(Path.join(root, "out"), "result")
               {:ok, %{"invalid" => self()}}
             end)

    refute File.exists?(Path.join(root, ".native-manifest.json.pending"))
    refute File.exists?(Path.join(root, "native-manifest.json"))
    File.rm_rf!(root)
    File.mkdir_p!(root)
    File.write!(Path.join(root, "out"), "result")

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(root, %{}, ["out"], fn -> :never end)
  end

  test "WCO-N01 rejects symlink ancestors, roots and artifacts", %{root: root} do
    outside = root <> "-outside"
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf!(outside) end)
    ancestor = root <> "-link"
    File.ln_s!(outside, ancestor)
    on_exit(fn -> File.rm(ancestor) end)

    assert {:error, :invalid_build_workspace} =
             Workspace.run(Path.join(ancestor, "workspace"), %{}, ["out"], fn -> :never end)

    assert {:error, :invalid_build_workspace} =
             Workspace.run(ancestor, %{}, ["out"], fn -> :never end)

    assert {:error, :invalid_build_artifact} =
             Workspace.run(root, %{}, ["bin/result"], fn ->
               File.mkdir_p!(Path.join(root, "bin"))
               File.write!(Path.join(outside, "result"), "outside")
               File.ln_s!(Path.join(outside, "result"), Path.join(root, "bin/result"))
               {:ok, base_manifest("unused")}
             end)

    assert File.read!(Path.join(outside, "result")) == "outside"
  end

  test "WCO-N01 rejects malformed, oversized and forged manifests read-only", %{root: root} do
    File.mkdir!(root)
    path = Path.join(root, "native-manifest.json")

    for bytes <- ["not-json", "[]", String.duplicate("x", 1_048_577)] do
      File.write!(path, bytes)

      assert {:error, :unrecognized_build_workspace} =
               Workspace.run(root, %{}, ["out"], fn -> :never end)

      assert File.read!(path) == bytes
    end

    for forged <- [%{}, %{"workspace" => %{"format_version" => 9}}] do
      bytes = Jason.encode!(forged)
      File.write!(path, bytes)

      assert {:error, :build_manifest_mismatch} =
               Workspace.run(root, %{}, ["out"], fn -> :never end)

      assert File.read!(path) == bytes
    end
  end

  test "WCO-N01 exclusive workspace ownership rejects a concurrent builder", %{root: root} do
    parent = self()

    owner =
      spawn(fn ->
        Workspace.run(root, %{}, ["out"], fn ->
          send(parent, :workspace_locked)

          receive do
            :finish -> {:error, :stopped}
          end
        end)
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert_receive :workspace_locked

    assert {:error, :build_workspace_locked} =
             Workspace.run(root, %{}, ["out"], fn -> flunk("duplicate builder ran") end)

    send(owner, :finish)
    monitor = Process.monitor(owner)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
  end

  test "WCO-N01 digest streams content and rejects non-files", %{root: root} do
    File.write!(root, String.duplicate("abc", 400_000))
    expected = Base.encode16(:crypto.hash(:sha256, File.read!(root)), case: :lower)
    assert {:ok, ^expected} = Workspace.digest(root)
    assert {:error, :invalid_build_artifact} = Workspace.digest(nil)
    assert {:error, :invalid_build_workspace} = Workspace.run(root, %{}, ["out"], fn -> :never end)
  end

  defp build_fixture(root) do
    executable = Path.join(root, "bin/wotex-coap-oscore")
    File.mkdir_p!(Path.dirname(executable))
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "logs"))
    File.write!(executable, "reviewed-native-fixture")
    File.chmod!(executable, 0o750)
    File.write!(Path.join(root, "lib/libcoap-3.a"), "static-library")
    File.write!(Path.join(root, "logs/build.log"), "bounded build output")
    {:ok, base_manifest(digest(executable))}
  end

  defp base_manifest(executable_hash) do
    %{
      "schema" => "wotex.coap.native@1",
      "backend" => %{"name" => "libcoap", "version" => "4.3.5", "revision" => @revision},
      "executables" => %{"wotex-coap-oscore" => %{"sha256" => executable_hash}},
      "build" => %{"features" => ["oscore"]}
    }
  end

  defp digest(path) do
    {:ok, digest} = Workspace.digest(path)
    digest
  end

  defp snapshot(path) do
    path
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.map(fn file ->
      stat = File.lstat!(file)

      attributes =
        Map.take(stat, [:size, :type, :mode, :links, :inode, :uid, :gid, :mtime, :ctime])

      {Path.relative_to(file, path), attributes, if(stat.type == :regular, do: File.read!(file))}
    end)
  end
end
