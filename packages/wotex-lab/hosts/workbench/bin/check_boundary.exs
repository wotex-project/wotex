# Boundary scan for the explicit Phoenix host. Runs with Elixir alone.

defmodule WotexLabWorkbench.Check.Boundary do
  @moduledoc false

  @unsafe ~r/(Application\.(put_env|put_all_env|ensure_all_started)\(|String\.to_atom\(|:erlang\.binary_to_atom\(|apps_path:|git:|github:)/
  @machine_path ~r{/(?:U)sers/|/(?:h)ome/}
  @explicit_bootstrap "boundary: explicit bootstrap inside the disposable worker process"

  @spec run() :: :ok
  def run do
    source = files(["lib/**/*.{ex,exs}", "config/*.{ex,exs}", "mix.exs"])

    refuse(
      scan(source, @unsafe, @explicit_bootstrap),
      "implicit activation, atom creation or source dependency"
    )

    refuse(scan(publishable(), @machine_path), "machine-local path in host source")
    IO.puts("boundary: explicit host composition and consumer-neutral source")
  end

  defp publishable do
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
        IO.puts(:stderr, "tracked host inventory failed (#{status}): #{output}")
        System.halt(1)
    end
  end

  defp files(patterns) do
    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&File.regular?/1)
  end

  defp scan(files, pattern, allowed_marker \\ nil) do
    Enum.flat_map(files, fn file ->
      lines =
        file
        |> File.stream!()
        |> Enum.to_list()

      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, number} ->
        previous = if number > 1, do: Enum.at(lines, number - 2)

        Regex.match?(pattern, line) and
          not (marker?(line, allowed_marker) or marker?(previous, allowed_marker))
      end)
      |> Enum.map(fn {line, number} -> "#{file}:#{number}:#{String.trim_trailing(line)}" end)
    end)
  end

  defp marker?(_, nil), do: false
  defp marker?(line, marker) when is_binary(line), do: String.contains?(line, marker)
  defp marker?(_, _), do: false

  defp refuse([], _), do: :ok

  defp refuse(hits, message) do
    Enum.each(hits, &IO.puts(:stderr, &1))
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

WotexLabWorkbench.Check.Boundary.run()
