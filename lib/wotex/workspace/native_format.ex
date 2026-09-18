defmodule Wotex.Workspace.NativeFormat do
  @moduledoc """
  clang-format on the changed lines of first-party C and C++ sources.

  For each file with changed ranges (`Wotex.Workspace.ChangedLines`),
  clang-format formats those ranges (`--lines=FIRST:LAST`; a new file in
  full) with the root `.clang-format`, and the result is compared with the
  file. A difference fails the check and is printed as `file:line` hunks;
  with `fix: true` the formatted text is written back instead.

  A `.h` file is formatted as C: clang-format treats `.h` as C++, so the
  header is formatted through a temporary `.c` copy.
  """

  alias Wotex.Workspace.ChangedLines
  alias Wotex.Workspace.NativeFiles

  @type result :: :ok | {:changed, String.t()} | {:fixed, Path.t()} | {:error, String.t()}

  @typedoc "Runs clang-format with arguments and returns `{stdout, status}` (tests replace it)."
  @type formatter :: ([String.t()] -> {String.t(), non_neg_integer()})

  @doc """
  Checks (or with `fix: true` rewrites) `file` (repository-relative, below
  `root`) on `ranges`. `formatter` runs clang-format.
  """
  @spec file(Path.t(), [ChangedLines.range()] | :all, Path.t(), formatter(), boolean()) :: result()
  def file(file, ranges, root, formatter, fix?) do
    source = Path.join(root, file)
    original = File.read!(source)

    with_input(file, original, fn input ->
      args = [
        input,
        "--style=file:" <> Path.join(root, ".clang-format") | ChangedLines.lines_arguments(ranges)
      ]

      case formatter.(args) do
        {^original, 0} ->
          :ok

        {formatted, 0} when fix? ->
          write(source, formatted, file)

        {formatted, 0} ->
          {:changed, render(file, original, formatted)}

        {output, status} ->
          {:error, "clang-format failed on #{file} (#{status}): #{String.trim(output)}"}
      end
    end)
  end

  @doc """
  Renders the difference between `original` and `formatted` as hunks headed
  `file:line:` with `-` and `+` lines.
  """
  @spec render(Path.t(), String.t(), String.t()) :: String.t()
  def render(file, original, formatted) do
    original
    |> String.split("\n")
    |> List.myers_difference(String.split(formatted, "\n"))
    |> hunks()
    |> Enum.map_join("\n", fn {line, lines} -> Enum.join(["#{file}:#{line}:" | lines], "\n") end)
  end

  @doc """
  Groups a `List.myers_difference/2` script into `{first_original_line,
  ["-old", "+new"]}` hunks.
  """
  @spec hunks([{:eq | :del | :ins, [String.t()]}]) :: [{pos_integer(), [String.t()]}]
  def hunks(script) do
    {_, hunks, current} =
      Enum.reduce(script, {1, [], nil}, fn
        {:eq, lines}, {line, hunks, current} ->
          {line + length(lines), flush(hunks, current), nil}

        {:del, lines}, {line, hunks, current} ->
          {line + length(lines), hunks, add(current, line, "-", lines)}

        {:ins, lines}, {line, hunks, current} ->
          {line, hunks, add(current, line, "+", lines)}
      end)

    Enum.reverse(flush(hunks, current))
  end

  defp write(source, formatted, file) do
    File.write!(source, formatted)
    {:fixed, file}
  end

  defp add(nil, line, sign, lines), do: {line, Enum.map(lines, &(sign <> &1))}
  defp add({start, acc}, _, sign, lines), do: {start, acc ++ Enum.map(lines, &(sign <> &1))}

  defp flush(hunks, nil), do: hunks
  defp flush(hunks, hunk), do: [hunk | hunks]

  defp with_input(file, original, fun) do
    if Path.extname(file) == ".h" and NativeFiles.language(file) == :c do
      directory =
        Path.join(System.tmp_dir!(), "wotex-native-format-#{System.unique_integer([:positive])}")

      File.mkdir_p!(directory)

      try do
        input = Path.join(directory, Path.rootname(Path.basename(file)) <> ".c")
        File.write!(input, original)
        fun.(input)
      after
        File.rm_rf!(directory)
      end
    else
      fun.(file)
    end
  end
end
