# Boundary scan for the explicit Phoenix host. Runs with Elixir alone.

defmodule WotexLabWorkbench.Check.Boundary do
  @moduledoc false

  @unsafe ~r/(Application\.(put_env|put_all_env|ensure_all_started)\(|String\.to_atom\(|:erlang\.binary_to_atom\(|apps_path:|git:|github:)/
  @machine_path ~r{/(?:U)sers/|/(?:h)ome/}
  @excluded ~w(.git deps _build cover doc priv/plts priv/static/vendor)

  def run do
    source = files(["lib/**/*.{ex,exs}", "config/*.{ex,exs}", "mix.exs"])
    refuse(scan(source, @unsafe), "implicit activation, atom creation or source dependency")
    refuse(scan(publishable(), @machine_path), "machine-local path in host source")
    IO.puts("boundary: explicit host composition and consumer-neutral source")
  end

  defp publishable do
    "**/*"
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&excluded?/1)
    |> Enum.filter(&File.regular?/1)
  end

  defp files(patterns),
    do: patterns |> Enum.flat_map(&Path.wildcard/1) |> Enum.filter(&File.regular?/1)

  defp excluded?(path) do
    segments = Path.split(path)

    Enum.any?(@excluded, fn excluded ->
      path == excluded or String.starts_with?(path, excluded <> "/")
    end) or
      Enum.any?(segments, &(&1 in ~w(.git deps _build cover doc)))
  end

  defp scan(files, pattern) do
    Enum.flat_map(files, fn file ->
      file
      |> File.stream!()
      |> Stream.with_index(1)
      |> Enum.filter(fn {line, _number} -> Regex.match?(pattern, line) end)
      |> Enum.map(fn {line, number} -> "#{file}:#{number}:#{String.trim_trailing(line)}" end)
    end)
  end

  defp refuse([], _message), do: :ok

  defp refuse(hits, message) do
    Enum.each(hits, &IO.puts(:stderr, &1))
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

WotexLabWorkbench.Check.Boundary.run()
