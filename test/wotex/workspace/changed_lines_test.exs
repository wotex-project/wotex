defmodule Wotex.Workspace.ChangedLinesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.ChangedLines
  alias WotexWorkspace.Fixtures

  @diff """
  diff --git a/packages/p/a.c b/packages/p/a.c
  index 1111111..2222222 100644
  --- a/packages/p/a.c
  +++ b/packages/p/a.c
  @@ -3 +3 @@ int main(void) {
  -    return 1;
  +    return 0;
  @@ -10,0 +11,4 @@ static int helper(void) {
  +static int added(void) {
  +    return 2;
  +}
  +
  @@ -20,3 +24,0 @@ static int removed(void) {
  -a
  -b
  -c
  diff --git a/packages/p/new.h b/packages/p/new.h
  new file mode 100644
  --- /dev/null
  +++ b/packages/p/new.h
  @@ -0,0 +1,2 @@
  +#pragma once
  +int f(void);
  diff --git a/packages/p/gone.c b/packages/p/gone.c
  deleted file mode 100644
  --- a/packages/p/gone.c
  +++ /dev/null
  @@ -1,2 +0,0 @@
  -int gone;
  -int more;
  diff --git a/packages/p/only_deleted.c b/packages/p/only_deleted.c
  --- a/packages/p/only_deleted.c
  +++ b/packages/p/only_deleted.c
  @@ -5 +4,0 @@
  -int x;
  """

  test "parses added and modified ranges of the new file" do
    assert ChangedLines.parse(@diff) == %{
             "packages/p/a.c" => [{3, 3}, {11, 14}],
             "packages/p/new.h" => [{1, 2}]
           }

    assert ChangedLines.parse("") == %{}
  end

  test "turns ranges into clang-format --lines arguments" do
    assert ChangedLines.lines_arguments([{3, 3}, {11, 14}]) == ["--lines=3:3", "--lines=11:14"]
    assert ChangedLines.lines_arguments(:all) == []
  end

  describe "ranges/3 in a repository" do
    setup context do
      root = Fixtures.tmp_dir(context)
      git!(root, ["init", "--quiet", "--initial-branch=main"])
      Fixtures.write!(root, "packages/p/a.c", Enum.map_join(1..10, "", &"int v#{&1};\n"))
      commit!(root, "base")
      %{root: root}
    end

    test "while .clang-format is uncommitted, only uncommitted changes count", %{root: root} do
      git!(root, ["checkout", "--quiet", "-b", "topic"])
      Fixtures.write!(root, "packages/p/a.c", Enum.map_join(1..10, "", &"int w#{&1};\n"))
      commit!(root, "rewrite on the branch")
      Fixtures.write!(root, ".clang-format", "BasedOnStyle: LLVM\n")
      edit_line!(root, "packages/p/a.c", 4, "int  edited;")
      Fixtures.write!(root, "packages/p/new.c", "int n;\n")

      assert ChangedLines.comparison("main", root) == "HEAD"

      assert ChangedLines.ranges(["packages/p/a.c", "packages/p/new.c"], "main", root) ==
               {:ok, %{"packages/p/a.c" => [{4, 4}], "packages/p/new.c" => :all}}
    end

    test "lines older than the commit that introduced .clang-format are not reported", %{
      root: root
    } do
      git!(root, ["checkout", "--quiet", "-b", "topic"])
      edit_line!(root, "packages/p/a.c", 2, "int before_rules;")
      commit!(root, "change before the rules")
      Fixtures.write!(root, ".clang-format", "BasedOnStyle: LLVM\n")
      commit!(root, "introduce the rules")
      introduced = String.trim(git!(root, ["rev-parse", "HEAD"]))
      edit_line!(root, "packages/p/a.c", 7, "int after_rules;")
      commit!(root, "change after the rules")

      assert ChangedLines.comparison("main", root) == introduced

      assert ChangedLines.ranges(["packages/p/a.c"], "main", root) ==
               {:ok, %{"packages/p/a.c" => [{7, 7}]}}
    end

    test "once the rules predate the branch, the merge base applies", %{root: root} do
      Fixtures.write!(root, ".clang-format", "BasedOnStyle: LLVM\n")
      commit!(root, "introduce the rules on main")
      merge_base = String.trim(git!(root, ["rev-parse", "HEAD"]))
      git!(root, ["checkout", "--quiet", "-b", "topic"])
      edit_line!(root, "packages/p/a.c", 1, "int first;")
      commit!(root, "branch change")
      edit_line!(root, "packages/p/a.c", 9, "int ninth;")

      assert ChangedLines.comparison("main", root) == merge_base

      assert ChangedLines.ranges(["packages/p/a.c"], "main", root) ==
               {:ok, %{"packages/p/a.c" => [{1, 1}, {9, 9}]}}

      assert ChangedLines.ranges([], "main", root) == {:ok, %{}}
      assert {:error, message} = ChangedLines.ranges(["packages/p/a.c"], "no-such-ref", root)
      assert message =~ "git diff failed"
    end
  end

  defp edit_line!(root, file, line, text) do
    path = Path.join(root, file)

    lines =
      path
      |> File.read!()
      |> String.split("\n")
      |> List.replace_at(line - 1, text)
      |> Enum.join("\n")

    File.write!(path, lines)
  end

  defp commit!(root, message) do
    git!(root, ["add", "."])

    git!(root, ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", message])
  end

  defp git!(root, args) do
    {output, 0} =
      System.cmd("git", args, cd: root, env: [{"GIT_CONFIG_NOSYSTEM", "1"}], stderr_to_stdout: true)

    output
  end
end
