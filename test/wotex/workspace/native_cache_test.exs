defmodule Wotex.Workspace.NativeCacheTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.CompileDb
  alias Wotex.Workspace.NativeCache
  alias Wotex.Workspace.NativeSuite
  alias WotexWorkspace.Fixtures

  describe "NativeCache" do
    test "the key depends on the suite and on every file's path and content", context do
      root = Fixtures.tmp_dir(context)
      Fixtures.write!(root, "packages/p/a.c", "int a;\n")
      Fixtures.write!(root, "packages/p/b.c", "int b;\n")
      Fixtures.write!(root, "packages/p/README.md", "docs\n")
      package = Path.join(root, "packages/p")
      files = ["packages/p/a.c", "packages/p/b.c", "packages/p/README.md", "packages/p/missing.c"]
      suite = %NativeSuite{name: "sdk", build: "p.native.build"}

      digests = NativeCache.digests(files, package, root)
      assert Enum.map(digests, &elem(&1, 0)) == ["a.c", "b.c"]

      key = NativeCache.key(suite, digests)
      assert key =~ ~r/^[0-9a-f]{16}$/
      assert NativeCache.key(suite, Enum.reverse(digests)) == key
      refute NativeCache.key(%{suite | build: "other"}, digests) == key
      refute NativeCache.key(%{suite | name: "other"}, digests) == key

      # Compile and test commands and containers do not change what the build
      # produces, so they keep the workspace.
      container = %{dockerfile: "d", platform: nil, volumes: []}
      command = %{run: ["true"], env: [], cd: nil, stdout: nil}

      assert NativeCache.key(
               %{
                 suite
                 | requires: ["docker"],
                   container: container,
                   prepare: [command],
                   test: [command]
               },
               digests
             ) == key

      File.write!(Path.join(package, "b.c"), "int changed;\n")
      refute NativeCache.key(suite, NativeCache.digests(files, package, root)) == key
    end

    test "prune keeps the current workspace, its lock and scratch", context do
      dir = Fixtures.tmp_dir(context)

      for entry <- ~w(aaaa aaaa.lock scratch bbbb bbbb.lock),
          do: File.mkdir_p!(Path.join(dir, entry))

      assert NativeCache.prune(dir, "aaaa") == :ok
      assert Enum.sort(File.ls!(dir)) == ~w(aaaa aaaa.lock scratch)
      assert NativeCache.prune(Path.join(dir, "absent"), "aaaa") == :ok
    end

    test "resolves symbolic links and honours WOTEX_NATIVE_CACHE", context do
      dir = Fixtures.tmp_dir(context)
      real = Path.join(dir, "real")
      File.mkdir_p!(Path.join(real, "inner"))
      File.ln_s!(real, Path.join(dir, "link"))

      assert NativeCache.real_path(Path.join(dir, "link/inner/new")) ==
               Path.join(NativeCache.real_path(real), "inner/new")

      assert NativeCache.root(fn "WOTEX_NATIVE_CACHE" -> Path.join(dir, "link") end) ==
               NativeCache.real_path(real)

      assert NativeCache.root(fn _ -> nil end) =~ ~r{/wotex-native$}
      assert NativeCache.variable() == "WOTEX_NATIVE_CACHE"

      scratch = NativeCache.reset!(Path.join(dir, "scratch"))
      File.write!(Path.join(scratch, "x"), "")
      assert File.ls!(NativeCache.reset!(scratch)) == []

      suite = %NativeSuite{name: "sdk"}
      assert NativeCache.suite_dir("/c", "p", suite) == "/c/p/sdk"
    end
  end

  describe "CompileDb" do
    test "reads, synthesizes and merges entries by real path", context do
      dir = Fixtures.tmp_dir(context)
      File.mkdir_p!(Path.join(dir, "src"))
      File.ln_s!(Path.join(dir, "src"), Path.join(dir, "linked"))
      real_src = NativeCache.real_path(Path.join(dir, "src"))

      database =
        Fixtures.write!(
          dir,
          "db/compile_commands.json",
          JSON.encode!([
            %{"directory" => Path.join(dir, "linked"), "file" => "a.c", "command" => "cc -c a.c"},
            %{"directory" => dir, "file" => "no-command.c"},
            %{"file" => "no-directory.c", "command" => "cc"}
          ])
        )

      assert {:ok, [entry]} = CompileDb.read(database)
      assert entry["file"] == "a.c"

      synthesized = CompileDb.entry(Path.join(real_src, "a.c"), ["-std=c11"], dir)
      assert synthesized["arguments"] == ["cc", "-std=c11", "-c", Path.join(real_src, "a.c")]

      assert CompileDb.entry("/x/b.cpp", ["-std=c++17"], "/x")["arguments"] == [
               "c++",
               "-std=c++17",
               "-c",
               "/x/b.cpp"
             ]

      merged = CompileDb.merge([[entry], [synthesized]])
      assert [%{"file" => file, "command" => "cc -c a.c"}] = merged
      assert file == Path.join(real_src, "a.c")
      assert CompileDb.files(merged) == MapSet.new([file])

      written = CompileDb.write!(Path.join(dir, "out"), merged)
      assert {:ok, [_]} = CompileDb.read(written)

      assert {:error, message} = CompileDb.read(Path.join(dir, "missing.json"))
      assert message =~ "no such file"
      File.write!(Path.join(dir, "bad.json"), "{}")
      assert {:error, message} = CompileDb.read(Path.join(dir, "bad.json"))
      assert message =~ "not a compilation database"
    end
  end
end
