# Consumer-neutral source scan. Runs with Elixir alone from the package
# directory, and in the full gate: `elixir bin/check_boundary.exs`.

defmodule Wotex.Zigbee.Check.Boundary do
  @moduledoc """
  Scans the package for framework, umbrella and machine-local dependencies
  that would break its standalone Hex consumer boundary.
  """

  @library ~r{(Application\.start\(|use Application|use Ash|use Phoenix|Ecto\.Repo|Oban\.)}
  @umbrella ~r{apps_path[[:space:]]*:}
  @machine_path ~r{([/]Users[/]|[/]home[/])}
  @excluded ~w(.git .elixir_ls _build cover deps doc priv/plts)

  @spec main() :: :ok
  def main do
    scan(["lib", "test", "mix.exs"], @library, "consumer-neutral library boundary violation")
    scan(["mix.exs"], @umbrella, "umbrella configuration is forbidden")
    scan(["."], @machine_path, "machine-local path found")
    IO.puts("boundary scan passed")
  end

  defp scan(roots, pattern, message) do
    hits = roots |> Enum.flat_map(&files/1) |> Enum.flat_map(&matches(&1, pattern))

    if hits != [] do
      Enum.each(hits, &IO.puts/1)
      IO.puts(:stderr, message)
      System.halt(1)
    end
  end

  defp files(path) do
    cond do
      path in @excluded -> []
      File.dir?(path) -> path |> File.ls!() |> Enum.sort() |> Enum.flat_map(&files(child(path, &1)))
      File.regular?(path) -> [path]
      true -> []
    end
  end

  defp child(".", name), do: name
  defp child(path, name), do: Path.join(path, name)

  defp matches(path, pattern) do
    with {:ok, content} <- File.read(path),
         true <- String.valid?(content) do
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _number} -> Regex.match?(pattern, line) end)
      |> Enum.map(fn {line, number} -> "#{path}:#{number}: #{line}" end)
    else
      _other -> []
    end
  end
end

Wotex.Zigbee.Check.Boundary.main()
