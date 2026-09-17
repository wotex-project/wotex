defmodule Wotex.Check.Boundary do
  @moduledoc false

  @library ~r{(Application\.start\(|use Ash|use Phoenix|[A-Z][A-Za-z0-9_.]*\.Repo|Ecto\.Repo|Oban\.)}
  @consumer_path ~r{([/]Users[/]|[/]home[/])}
  @umbrella ~r{apps_path[[:space:]]*:}

  @excluded [
    ".git",
    ".elixir_ls",
    ".fetch",
    ".lexical",
    "_build",
    "cover",
    "deps",
    "doc",
    "docs/tasks/inbox.md",
    "docs/tasks/local",
    "priv/plts"
  ]

  @spec main() :: :ok
  def main do
    scan(["lib", "test", "mix.exs"], @library, "consumer-neutral library boundary violation")
    scan(["."], @consumer_path, "consumer filesystem path found")
    scan(["mix.exs"], @umbrella, "umbrella configuration is forbidden")
  end

  defp scan(roots, pattern, message) do
    hits = roots |> Enum.flat_map(&files/1) |> Enum.flat_map(&matches(&1, pattern))

    unless hits == [] do
      Enum.each(hits, &IO.puts/1)
      IO.puts(:stderr, message)
      System.halt(1)
    end

    :ok
  end

  defp files(root) do
    cond do
      File.regular?(root) -> [root]
      File.dir?(root) -> descend(root, "")
      true -> []
    end
  end

  defp descend(root, relative) do
    path = path(root, relative)

    cond do
      relative in @excluded ->
        []

      File.dir?(path) ->
        path |> File.ls!() |> Enum.sort() |> Enum.flat_map(&child(root, relative, &1))

      File.regular?(path) ->
        [path]

      true ->
        []
    end
  end

  defp child(root, "", name), do: descend(root, name)
  defp child(root, relative, name), do: descend(root, relative <> "/" <> name)

  defp path(root, ""), do: root
  defp path(".", relative), do: relative
  defp path(root, relative), do: root <> "/" <> relative

  defp matches(path, pattern) do
    case File.read(path) do
      {:ok, content} -> lines(path, content, pattern)
      {:error, _reason} -> []
    end
  end

  defp lines(path, content, pattern) do
    if String.contains?(content, <<0>>) do
      []
    else
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _number} -> Regex.match?(pattern, line) end)
      |> Enum.map(fn {line, number} -> "#{path}:#{number}:#{line}" end)
    end
  end
end

Wotex.Check.Boundary.main()
