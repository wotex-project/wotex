# Boundary scan for the Lab source tree: explicit composition and
# consumer-neutral source. Runs with Elixir alone: `elixir bin/check_boundary.exs`.

defmodule Wotex.Lab.Check.Boundary do
  @moduledoc false

  @activation ~r/(Application\.(put_env|put_all_env|start|ensure_all_started)\(|String\.to_atom\(|:erlang\.binary_to_atom\(|use Application|apps_path:|git:|github:)/
  @machine_path ~r/([\/]Users[\/]|[\/]home[\/])/

  @spec run() :: :ok
  def run do
    activation = scan(source_files(["lib/**/*.{ex,exs}", "mix.exs"]), @activation)

    if activation != [] do
      print(activation)
      IO.puts(:stderr, "implicit activation, mutable global policy or source dependency detected")
      System.halt(1)
    end

    paths = scan(publishable_files(), @machine_path)

    if paths != [] do
      print(paths)
      IO.puts(:stderr, "machine-local path in publishable source")
      System.halt(1)
    end

    IO.puts("boundary: explicit composition and consumer-neutral source")
  end

  defp source_files(patterns) do
    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&File.regular?/1)
  end

  defp publishable_files do
    case System.cmd(
           "git",
           ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
           env: [{"GIT_TERMINAL_PROMPT", "0"}],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> :binary.split(<<0>>, [:global])
        |> Enum.filter(&(&1 != "" and File.regular?(&1)))

      {output, status} ->
        IO.puts(:stderr, "tracked source inventory failed (#{status}): #{output}")
        System.halt(1)
    end
  end

  defp scan(files, regex) do
    Enum.flat_map(files, fn file ->
      file
      |> File.stream!()
      |> Stream.with_index(1)
      |> Enum.filter(fn {line, _} -> Regex.match?(regex, line) end)
      |> Enum.map(fn {line, number} -> "#{file}:#{number}:#{String.trim_trailing(line)}" end)
    end)
  end

  defp print(hits), do: Enum.each(hits, &IO.puts/1)
end

Wotex.Lab.Check.Boundary.run()
