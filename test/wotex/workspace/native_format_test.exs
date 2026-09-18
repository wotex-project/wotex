defmodule Wotex.Workspace.NativeFormatTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeFormat
  alias WotexWorkspace.Fixtures

  setup context do
    root = Fixtures.tmp_dir(context)
    Fixtures.write!(root, "packages/p/a.c", "int  a;\nint b;\n")
    Fixtures.write!(root, "packages/p/a.h", "int  h;\n")
    %{root: root}
  end

  defp formatter(parent, output, status \\ 0) do
    fn args ->
      send(parent, {:args, args})
      {output, status}
    end
  end

  test "passes when clang-format leaves the changed lines alone", %{root: root} do
    assert NativeFormat.file(
             "packages/p/a.c",
             [{2, 2}],
             root,
             formatter(self(), "int  a;\nint b;\n"),
             false
           ) ==
             :ok

    assert_received {:args, args}

    assert args == [
             "packages/p/a.c",
             "--style=file:" <> Path.join(root, ".clang-format"),
             "--lines=2:2"
           ]
  end

  test "reports the difference as file:line hunks", %{root: root} do
    assert {:changed, diff} =
             NativeFormat.file(
               "packages/p/a.c",
               :all,
               root,
               formatter(self(), "int a;\nint b;\n"),
               false
             )

    assert diff == "packages/p/a.c:1:\n-int  a;\n+int a;"
    assert_received {:args, ["packages/p/a.c", _style]}
  end

  test "writes the formatted text with fix", %{root: root} do
    assert NativeFormat.file(
             "packages/p/a.c",
             :all,
             root,
             formatter(self(), "int a;\nint b;\n"),
             true
           ) ==
             {:fixed, "packages/p/a.c"}

    assert File.read!(Path.join(root, "packages/p/a.c")) == "int a;\nint b;\n"
  end

  test "formats a .h header as C through a temporary .c copy", %{root: root} do
    parent = self()

    format = fn args ->
      input = hd(args)
      send(parent, {:input, input, File.read!(input)})
      {"int h;\n", 0}
    end

    assert NativeFormat.file("packages/p/a.h", [{1, 1}], root, format, true) ==
             {:fixed, "packages/p/a.h"}

    assert_received {:input, input, "int  h;\n"}
    assert Path.extname(input) == ".c"
    refute File.exists?(input)
    assert File.read!(Path.join(root, "packages/p/a.h")) == "int h;\n"
  end

  test "reports a clang-format failure", %{root: root} do
    assert {:error, message} =
             NativeFormat.file(
               "packages/p/a.c",
               :all,
               root,
               formatter(self(), "bad config", 1),
               false
             )

    assert message == "clang-format failed on packages/p/a.c (1): bad config"
  end

  test "groups an edit script into hunks" do
    script = List.myers_difference(~w(a b c d e), ~w(a B c d E F))
    assert NativeFormat.hunks(script) == [{2, ["-b", "+B"]}, {5, ["-e", "+E", "+F"]}]
    assert NativeFormat.render("f.c", "x\ny\n", "x\ny\nz\n") == "f.c:3:\n+z"
  end
end
