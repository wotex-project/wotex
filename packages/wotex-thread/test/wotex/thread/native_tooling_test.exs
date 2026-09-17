defmodule Wotex.Thread.NativeToolingTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.BuildFixture
  alias Wotex.Thread.Native.{Bootstrap, Command, Source, Workspace}

  @moduletag requirements: ["WTH-B01"]
  @guardian_source "priv/openthread/build_command.c"

  setup do
    root = Path.join(File.cwd!(), ".wotex-thread-tooling-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WTH-B01 source helpers refuse non-binary, linked and unreadable inputs", context do
    for call <- [
          fn -> Source.fetch(:url, "/tmp/target", "digest") end,
          fn -> Source.digest(:path) end,
          fn -> Source.tree_digest(:path) end,
          fn -> Source.file_hashes(:path) end,
          fn -> Source.copy_tree(:source, "/tmp/destination") end,
          fn -> Source.validate_archive(:path, "root") end
        ] do
      assert {:error, code} = call.()
      assert code in ~w(invalid_source_download invalid_source_file invalid_source_tree
               invalid_source_archive)a
    end

    link = Path.join(context.root, "link")
    File.ln_s!("/nowhere", link)
    assert {:error, :invalid_source_file} = Source.digest(link)
    assert {:error, :invalid_source_tree} = Source.tree_digest(link)
    assert {:error, :invalid_source_tree} = Source.file_hashes(link)
    assert {:error, :invalid_source_tree} = Source.copy_tree(link, Path.join(context.root, "copy"))

    tree = Path.join(context.root, "tree")
    File.mkdir_p!(Path.join(tree, "inner"))
    File.ln_s!("/nowhere", Path.join(tree, "inner/link"))
    assert {:error, :invalid_source_tree} = Source.tree_digest(tree)
    assert {:error, :invalid_source_tree} = Source.file_hashes(tree)
    assert {:error, :invalid_source_tree} = Source.copy_tree(tree, Path.join(context.root, "out"))
  end

  test "WTH-B01 a copy refuses an occupied destination and an unreadable archive", context do
    source = Path.join(context.root, "source")
    File.mkdir_p!(source)
    File.write!(Path.join(source, "file"), "bytes")
    destination = Path.join(context.root, "destination")
    File.mkdir_p!(destination)
    File.mkdir_p!(Path.join(destination, "file"))
    assert {:error, :invalid_source_tree} = Source.copy_tree(source, destination)

    occupied = Path.join(context.root, "occupied")
    File.write!(occupied, "not a directory")
    assert {:error, :invalid_source_tree} = Source.copy_tree(source, occupied)

    File.write!(Path.join(destination, "other"), "old")
    File.write!(Path.join(source, "other"), "new")
    File.rm_rf!(Path.join(destination, "file"))
    assert :ok = Source.copy_tree(source, destination)
    assert File.read!(Path.join(destination, "other")) == "new"

    archive = Path.join(context.root, "archive.tar.gz")
    File.write!(archive, "not an archive")
    assert {:error, :invalid_source_archive} = Source.validate_archive(archive, "root")
    assert {:error, :invalid_source_archive} = Source.extract(archive, destination, "root")
    assert {:error, :invalid_source_archive} = Source.extract(archive, "relative", "root")
  end

  test "WTH-B01 a cached pinned transfer verifies its digest without any request", context do
    url = "https://codeload.github.com/openthread/openthread/tar.gz/#{String.duplicate("c3", 20)}"
    target = Path.join(context.root, "cached.tar.gz")
    File.write!(target, "cached bytes")
    digest = Base.encode16(:crypto.hash(:sha256, "cached bytes"), case: :lower)

    assert :ok = Source.fetch(url, target, digest)
    assert {:error, :source_hash_mismatch} = Source.fetch(url, target, String.duplicate("0", 64))

    assert {:error, :invalid_source_download} =
             Source.fetch("https://example.com/x", target, digest)

    assert {:error, :invalid_source_download} = Source.fetch(url, "relative", digest)
    assert {:error, :invalid_source_download} = Source.fetch(url, target, "short")

    directory = Path.join(context.root, "directory.tar.gz")
    File.mkdir_p!(directory)
    assert {:error, :invalid_source_download} = Source.fetch(url, directory, digest)
  end

  test "WTH-B01 a verified HTTPS transfer streams, digests and links the source", context do
    body = String.duplicate("source", 20_000)
    digest = Base.encode16(:crypto.hash(:sha256, body), case: :lower)
    target = Path.join(context.root, "transfer.tar.gz")

    {url, ssl} = BuildFixture.https_server(200, body)
    assert :ok = Source.transfer(url, target, digest, ssl)
    assert File.read!(target) == body
    refute File.exists?(target <> ".download")
    assert :ok = Source.transfer(url, target, digest, ssl)

    {url, ssl} = BuildFixture.https_server(200, body)
    mismatch = Path.join(context.root, "mismatch.tar.gz")

    assert {:error, :source_hash_mismatch} =
             Source.transfer(url, mismatch, String.duplicate("0", 64), ssl)

    refute File.exists?(mismatch) or File.exists?(mismatch <> ".download")

    {url, ssl} = BuildFixture.https_server(404, "absent", reason: "Not Found")
    absent = Path.join(context.root, "absent.tar.gz")
    assert {:error, :invalid_source_download} = Source.transfer(url, absent, digest, ssl)
    refute File.exists?(absent) or File.exists?(absent <> ".download")

    {url, ssl} = BuildFixture.https_server(200, body, close_after: 100)
    truncated = Path.join(context.root, "truncated.tar.gz")
    assert {:error, :invalid_source_download} = Source.transfer(url, truncated, digest, ssl)
    refute File.exists?(truncated)

    {url, ssl} = BuildFixture.https_server(200, body)
    untrusted = Keyword.put(ssl, :cacerts, [])

    assert {:error, :invalid_source_download} =
             Source.transfer(url, target <> ".2", digest, untrusted)

    assert {:error, :invalid_source_download} =
             Source.transfer(url, target, digest, verify: :verify_none)

    assert {:error, :invalid_source_download} =
             Source.transfer("http://localhost/x", target, digest, ssl)

    assert {:error, :invalid_source_download} = Source.transfer(url, target, digest, :ssl)
  end

  test "WTH-B01 executables are found in an explicit search path only when executable", context do
    directory = Path.join(context.root, "tools")
    File.mkdir_p!(directory)
    plain = Path.join(directory, "plain")
    File.write!(plain, "#!/bin/sh\nexit 0\n")
    File.chmod!(plain, 0o644)
    runnable = Path.join(directory, "runnable")
    File.write!(runnable, "#!/bin/sh\nexit 0\n")
    File.chmod!(runnable, 0o755)

    assert Source.executable("runnable", directory) == runnable
    assert Source.executable("plain", directory) == nil
    assert Source.executable("absent", directory) == nil
    assert Source.executable("sh", "/bin") == "/bin/sh"
    assert Source.executable("sh", nil) == System.find_executable("sh")
  end

  test "WTH-B01 module digests identify loaded build modules only", _context do
    assert {:ok, digest} = Source.module_digest(Wotex.Thread.Native.Build)
    assert digest =~ ~r/\A[0-9a-f]{64}\z/
    assert {:error, :invalid_source_module} = Source.module_digest(Absent.Build.Module)
  end

  test "WTH-B01 the guardian bootstrap requires absolute paths and reports failure", context do
    output = Path.join(context.root, "guardian")

    assert {:error, :invalid_bootstrap, %{output: <<>>, descendant_cleanup: :unverified}} =
             Bootstrap.compile("cc", source(), output, context.root)

    assert {:error, :invalid_bootstrap, _} = Bootstrap.compile(:cc, source(), output, context.root)

    broken = Path.join(context.root, "broken.c")
    File.write!(broken, "int main(void) { return missing_symbol; }\n")

    assert {:error, :bootstrap_failed, %{output: compiler, descendant_cleanup: :unverified}} =
             Bootstrap.compile("/usr/bin/cc", broken, output, context.root)

    assert compiler =~ "missing_symbol"
    refute File.exists?(output)

    assert {:error, :bootstrap_failed, %{output: <<>>}} =
             Bootstrap.compile("/usr/bin/absent-compiler", broken, output, context.root)
  end

  test "WTH-B01 a command step is refused before any process starts", context do
    guardian = Path.join(context.root, "build-command")
    assert {:ok, _} = Bootstrap.compile("/usr/bin/cc", source(), guardian, context.root)

    step = %{
      id: :probe,
      executable: "/bin/echo",
      cwd: context.root,
      args: ["one"],
      env: [{"PATH", "/usr/bin:/bin"}],
      timeout_ms: 1_000,
      output_bytes: 4_096,
      cleanup_ms: 1_000
    }

    assert {:ok, %{exit_status: 0, output: "one\n"}} = Command.run(guardian, step)

    for invalid <- [
          %{step | id: "probe"},
          %{step | executable: "echo"},
          %{step | cwd: "relative"},
          %{step | args: ["ok", :atom]},
          %{step | args: [String.duplicate("x", 8193)]},
          %{step | args: List.duplicate("x", 257)},
          %{step | args: "one"},
          %{step | env: [{"path", "/bin"}]},
          %{step | env: [{"PATH", "/bin"}, {"PATH", "/usr/bin"}]},
          %{step | env: [{:PATH, "/bin"}]},
          %{step | env: %{"PATH" => "/bin"}},
          %{step | timeout_ms: 0},
          %{step | output_bytes: 16_777_217},
          %{step | cleanup_ms: 5_001},
          Map.delete(step, :id),
          Map.put(step, :extra, true)
        ] do
      assert {:error, :invalid_command, %{output: <<>>, exit_status: nil}} =
               Command.run(guardian, invalid),
             inspect(invalid)
    end

    assert {:error, :invalid_command, _} = Command.run("relative", step)
    assert {:error, :invalid_command, _} = Command.run(guardian, %{step | executable: :echo})
    assert {:error, :invalid_command, _} = Command.run(:guardian, step)
    assert {:error, :invalid_command, _} = Command.run(guardian, %{step | env: [{"PATH", <<0>>}]})
  end

  test "WTH-B01 a workspace refuses invalid identities, artifacts and ancestors", context do
    identity = %{"source_revision" => "digest"}
    builder = fn -> {:ok, %{"tool" => "fixture"}} end
    workspace = Path.join(context.root, "build")

    for {path, identity, artifacts} <- [
          {"relative", identity, ["file"]},
          {"/", identity, ["file"]},
          {workspace, identity, []},
          {workspace, identity, ["file", "file"]},
          {workspace, identity, ["/absolute"]},
          {workspace, identity, ["../escape"]},
          {workspace, identity, ["native-manifest.json"]},
          {workspace, identity, [".wotex-thread-build.lock"]},
          {workspace, %{"source" => self()}, ["file"]},
          {workspace, "identity", ["file"]},
          {workspace, identity, List.duplicate("file", 65)}
        ] do
      assert {:error, :invalid_build_workspace} = Workspace.run(path, identity, artifacts, builder)
    end

    assert {:error, :invalid_build_workspace} = Workspace.run(workspace, identity, ["f"], :builder)
    assert {:error, :invalid_build_workspace} = Workspace.run(workspace, identity, [:file], builder)
    assert {:error, :invalid_build_workspace} = Workspace.run(:path, identity, ["file"], builder)
    assert {:ok, ^workspace, true} = Workspace.arguments(["--sanitizers", "--workspace", workspace])

    assert {:error, :invalid_build_workspace} =
             Workspace.run(workspace, identity, ["f"], builder, :other)

    link = Path.join(context.root, "link")
    File.ln_s!(context.root, link)

    assert {:error, :invalid_build_workspace} =
             Workspace.run(Path.join(link, "build"), identity, ["file"], builder)
  end

  test "WTH-B01 a workspace refuses unreadable state, builders and artifacts", context do
    identity = %{"source_revision" => "digest"}
    artifacts = ["output"]

    occupied = Path.join(context.root, "occupied")
    File.write!(occupied, "file")

    assert {:error, :invalid_build_workspace} =
             Workspace.run(occupied, identity, artifacts, fn -> {:ok, %{}} end)

    unrecognized = Path.join(context.root, "unrecognized")
    File.mkdir_p!(unrecognized)
    File.write!(Path.join(unrecognized, "stray"), "data")

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(unrecognized, identity, artifacts, fn -> {:ok, %{}} end)

    File.write!(Path.join(unrecognized, "native-manifest.json"), "not json")

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(unrecognized, identity, artifacts, fn -> {:ok, %{}} end)

    refused = Path.join(context.root, "refused")

    assert {:error, :build_workspace_changed} =
             Workspace.run(refused, identity, artifacts, fn -> :refused end)

    missing = Path.join(context.root, "missing-artifact")

    assert {:error, :invalid_build_artifact} =
             Workspace.run(missing, identity, artifacts, fn -> {:ok, %{}} end)

    linked = Path.join(context.root, "linked-artifact")

    builder = fn ->
      File.ln_s!("/nowhere", Path.join(linked, "output"))
      {:ok, %{}}
    end

    assert {:error, :invalid_build_artifact} = Workspace.run(linked, identity, artifacts, builder)

    existing = Path.join(context.root, "existing-empty")
    File.mkdir_p!(existing)

    assert {:ok, %{reused: false}} =
             Workspace.run(existing, identity, artifacts, fn ->
               File.write!(Path.join(existing, "output"), "bytes")
               {:ok, %{}}
             end)

    unencodable = Path.join(context.root, "unencodable")

    assert {:error, :invalid_build_manifest} =
             Workspace.run(unencodable, identity, artifacts, fn ->
               File.write!(Path.join(unencodable, "output"), "bytes")
               {:ok, %{"port" => self()}}
             end)
  end

  defp source, do: Application.app_dir(:wotex_thread, @guardian_source)
end
