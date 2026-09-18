defmodule Wotex.Workspace.CompileDbTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.CompileDb
  alias Wotex.Workspace.NativeCache
  alias WotexWorkspace.Fixtures

  # A temporary directory without symbolic links in its path, so that real
  # paths can be written out literally.
  setup context do
    %{dir: NativeCache.real_path(Fixtures.tmp_dir(context))}
  end

  describe "read/1" do
    test "keeps entries with a file, a directory and a command or arguments", %{dir: dir} do
      command = %{"directory" => "/src", "file" => "a.c", "command" => "cc -c a.c"}

      arguments = %{
        "directory" => "/src",
        "file" => "b.cpp",
        "arguments" => ["c++", "-c", "b.cpp"],
        "output" => "b.o"
      }

      invalid = [
        %{"directory" => "/src", "file" => "no-command.c"},
        %{"file" => "no-directory.c", "command" => "cc"},
        %{"directory" => "/src", "command" => "cc -c no-file.c"},
        %{"directory" => "/src", "file" => 1, "command" => "cc"},
        %{"directory" => "/src", "file" => "c.c", "arguments" => "cc -c c.c"},
        %{"directory" => "/src", "file" => "d.c", "command" => ["cc", "-c", "d.c"]},
        "cc -c e.c",
        nil
      ]

      path =
        Fixtures.write!(
          dir,
          "compile_commands.json",
          JSON.encode!([command | invalid] ++ [arguments])
        )

      assert CompileDb.read(path) == {:ok, [command, arguments]}
    end

    test "an empty list is an empty database", %{dir: dir} do
      path = Fixtures.write!(dir, "compile_commands.json", "[]")
      assert CompileDb.read(path) == {:ok, []}
    end

    test "anything but a JSON list is not a compilation database", %{dir: dir} do
      path = Path.join(dir, "compile_commands.json")

      for text <- ["{}", "null", ~s("cc"), "[", ""] do
        File.write!(path, text)

        assert CompileDb.read(path) == {:error, "#{path}: not a compilation database"},
               "for #{inspect(text)}"
      end
    end

    test "a file that cannot be read names the path and the reason", %{dir: dir} do
      missing = Path.join(dir, "missing.json")
      assert CompileDb.read(missing) == {:error, "#{missing}: no such file or directory"}
      assert CompileDb.read(dir) == {:error, "#{dir}: illegal operation on a directory"}
    end
  end

  describe "entry/3" do
    test "compiles C sources and headers with cc" do
      for file <- ["/src/a.c", "/src/include/a.h"] do
        assert CompileDb.entry(file, ["-std=c11", "-Iinclude"], "/build") == %{
                 "directory" => "/build",
                 "file" => file,
                 "arguments" => ["cc", "-std=c11", "-Iinclude", "-c", file]
               }
      end
    end

    test "compiles every other file with c++" do
      for extension <- ~w(.cc .cpp .cxx .hh .hpp .hxx) do
        file = "/src/a" <> extension

        assert CompileDb.entry(file, [], "/src")["arguments"] == ["c++", "-c", file],
               "for #{extension}"
      end
    end
  end

  describe "merge/1" do
    test "resolves each file against its directory", %{dir: dir} do
      relative = %{"directory" => Path.join(dir, "build"), "file" => "../src/a.c", "command" => "a"}
      absolute = %{"directory" => "/elsewhere", "file" => Path.join(dir, "b.c"), "command" => "b"}

      assert CompileDb.merge([[relative, absolute]]) == [
               Map.put(relative, "file", Path.join(dir, "src/a.c")),
               Map.put(absolute, "file", Path.join(dir, "b.c"))
             ]
    end

    test "keeps the first entry for a file, also when a link names it", %{dir: dir} do
      File.mkdir_p!(Path.join(dir, "src"))
      File.ln_s!(Path.join(dir, "src"), Path.join(dir, "linked"))

      first = %{"directory" => Path.join(dir, "linked"), "file" => "a.c", "command" => "first"}
      other = %{"directory" => dir, "file" => "src/b.c", "arguments" => ["other"]}
      again = %{"directory" => Path.join(dir, "src"), "file" => "a.c", "arguments" => ["again"]}

      assert CompileDb.merge([[first], [other, again], [first]]) == [
               Map.put(first, "file", Path.join(dir, "src/a.c")),
               Map.put(other, "file", Path.join(dir, "src/b.c"))
             ]
    end

    test "no lists or empty lists merge to no entries" do
      assert CompileDb.merge([]) == []
      assert CompileDb.merge([[], []]) == []
    end
  end

  describe "files/1" do
    test "is the set of the entries' files" do
      entries = [%{"file" => "/src/a.c"}, %{"file" => "/src/b.c"}, %{"file" => "/src/a.c"}]

      assert CompileDb.files(entries) == MapSet.new(["/src/a.c", "/src/b.c"])
      assert CompileDb.files([]) == MapSet.new()
    end
  end

  describe "write!/2" do
    test "creates the directory and writes a database that read/1 accepts", %{dir: dir} do
      entries = [
        CompileDb.entry(Path.join(dir, "a.c"), ["-DX=1"], dir),
        %{"directory" => dir, "file" => "b.cpp", "command" => "c++ -c b.cpp"}
      ]

      out = Path.join(dir, "out/tidy")
      path = CompileDb.write!(out, entries)

      assert path == Path.join(out, "compile_commands.json")
      assert CompileDb.read(path) == {:ok, entries}
    end

    test "replaces an existing database", %{dir: dir} do
      CompileDb.write!(dir, [CompileDb.entry("/src/a.c", [], "/src")])
      path = CompileDb.write!(dir, [])

      assert CompileDb.read(path) == {:ok, []}
    end
  end
end
