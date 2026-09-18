defmodule Wotex.Workspace.ChangedLines do
  @moduledoc """
  The lines a change touches, for checking formatting on changed lines only.

  The existing C and C++ sources predate the repository's `.clang-format`, and
  formatting them whole would rewrite a fifth of their lines. The format check
  therefore applies to the lines a change adds or modifies, as
  `git clang-format --diff` does: the working tree (committed, staged and
  unstaged changes) is compared with a comparison commit (`git diff -U0
  <commit>`), and every added hunk yields a line range of the working-tree
  file. An untracked file counts as changed in full.

  The comparison commit is the merge base of `base` and `HEAD`, or the commit
  that introduced `.clang-format` when that is newer: lines that existed when
  the formatting rules arrived are not reported until a change touches them.
  While `.clang-format` is not committed yet, only uncommitted changes count.

  `parse/1` turns `git diff -U0` output into ranges; `ranges/3` runs Git.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Affected

  @typedoc "An inclusive, 1-based line range of the working-tree file."
  @type range :: {pos_integer(), pos_integer()}

  @typedoc "Changed ranges per repository-relative path; `:all` for a new, untracked file."
  @type changes :: %{Path.t() => [range()] | :all}

  @hunk ~r/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

  @doc """
  Parses `git diff -U0 --no-color` output. Hunks that only delete lines add
  no range; a deleted file adds no entry.
  """
  @spec parse(String.t()) :: %{Path.t() => [range()]}
  def parse(diff) do
    diff
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, &parse_line/2)
    |> elem(1)
    |> Map.new(fn {path, ranges} -> {path, Enum.reverse(ranges)} end)
    |> Map.reject(fn {_, ranges} -> ranges == [] end)
  end

  defp parse_line("+++ /dev/null", {_, acc}), do: {nil, acc}

  defp parse_line("+++ b/" <> path, {_, acc}), do: {path, Map.put_new(acc, path, [])}

  defp parse_line("@@ " <> _ = line, {file, acc}) when is_binary(file) do
    case Regex.run(@hunk, line) do
      [_, start, count] ->
        {file, add_range(acc, file, String.to_integer(start), String.to_integer(count))}

      [_, start] ->
        {file, add_range(acc, file, String.to_integer(start), 1)}

      nil ->
        {file, acc}
    end
  end

  defp parse_line(_, state), do: state

  defp add_range(acc, _, _, 0), do: acc

  defp add_range(acc, file, start, count),
    do: Map.update!(acc, file, &[{start, start + count - 1} | &1])

  @doc """
  The changed ranges of `paths` (repository-relative) since the comparison
  commit of `base` (default: `Wotex.Workspace.Affected.default_base/1`), see
  `comparison/2`. Paths without changes are absent from the result.
  """
  @spec ranges([Path.t()], String.t() | nil, Path.t()) :: {:ok, changes()} | {:error, String.t()}
  def ranges(paths, base \\ nil, root \\ Workspace.root())

  def ranges([], _, _), do: {:ok, %{}}

  def ranges(paths, base, root) do
    with {:ok, base} <- resolve_base(base, root),
         commit = comparison(base, root),
         {:ok, diff} <-
           git(
             ["diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", commit, "--" | paths],
             root
           ),
         {:ok, untracked} <-
           git(["ls-files", "-z", "--others", "--exclude-standard", "--" | paths], root) do
      new = Map.new(String.split(untracked, <<0>>, trim: true), &{&1, :all})
      wanted = MapSet.new(paths)

      changes =
        diff
        |> parse()
        |> Map.filter(fn {path, _} -> MapSet.member?(wanted, path) end)
        |> Map.merge(new)

      {:ok, changes}
    end
  end

  @doc "The `clang-format --lines=FIRST:LAST` arguments for `ranges`; none for `:all`."
  @spec lines_arguments([range()] | :all) :: [String.t()]
  def lines_arguments(:all), do: []

  def lines_arguments(ranges),
    do: Enum.map(ranges, fn {first, last} -> "--lines=#{first}:#{last}" end)

  defp resolve_base(nil, root), do: Affected.default_base(root)
  defp resolve_base(base, _), do: {:ok, base}

  @doc """
  The commit a change is compared with: the merge base of `base` and `HEAD`,
  or the commit that last introduced `.clang-format` when the merge base is
  its ancestor. `HEAD` while `.clang-format` is not committed.
  """
  @spec comparison(String.t(), Path.t()) :: String.t()
  def comparison(base, root \\ Workspace.root()) do
    merge_base = merge_base(base, root)

    case git(["log", "--diff-filter=A", "--format=%H", "HEAD", "--", ".clang-format"], root) do
      {:ok, ""} -> "HEAD"
      {:ok, output} -> newer(merge_base, hd(String.split(output, "\n", trim: true)), root)
      {:error, _} -> merge_base
    end
  end

  defp newer(merge_base, introduced, root) do
    case git(["merge-base", "--is-ancestor", merge_base, introduced], root) do
      {:ok, _} -> introduced
      {:error, _} -> merge_base
    end
  end

  defp merge_base(base, root) do
    case git(["merge-base", base, "HEAD"], root) do
      {:ok, output} -> String.trim(output)
      {:error, _} -> base
    end
  end

  defp git(args, root) do
    env = [{"GIT_TERMINAL_PROMPT", "0"}, {"GIT_OPTIONAL_LOCKS", "0"}]

    case System.cmd("git", args, cd: root, env: env, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, "git #{hd(args)} failed (#{status}): #{String.trim(output)}"}
    end
  end
end
