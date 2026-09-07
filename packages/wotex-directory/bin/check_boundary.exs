# Verifies the library boundary using Elixir only.
#
#     elixir bin/check_boundary.exs

defmodule CheckBoundary do
  @moduledoc false

  @excluded_roots [".git", "deps", "_build", "doc", "cover"]

  @boundary ~r/(Application\.start\(|use (Application|GenServer|Supervisor|Agent)|DynamicSupervisor\.|Task\.Supervisor|Registry\.|use Ash|use Phoenix|Ecto\.|Oban\.|Plug\.)/
  @umbrella ~r/apps_path[[:space:]]*:/
  @consumer_path ~r"([/]Users[/]|[/]home[/])"
  @module_definition ~r/^defmodule /

  def run do
    refuse(
      ["lib", "test", "mix.exs"],
      @boundary,
      "directory process, framework, or persistence boundary violation"
    )

    refuse(["mix.exs"], @umbrella, "umbrella configuration is forbidden")
    refuse(["."], @consumer_path, "consumer filesystem path found")

    Enum.each(sources("lib", ".ex"), fn source ->
      require_single_module(source, "source file must contain exactly one module")
    end)
  end

  defp refuse(roots, regex, message) do
    hits = Enum.flat_map(roots, &matches(&1, regex))

    unless hits == [] do
      Enum.each(hits, &IO.puts/1)
      abort(message)
    end
  end

  defp require_single_module(source, message) do
    modules =
      source
      |> read()
      |> String.split("\n")
      |> Enum.count(&Regex.match?(@module_definition, &1))

    unless modules == 1 do
      abort("#{message}: #{source}")
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end

  defp matches(root, regex) do
    Enum.flat_map(entries(root), fn path ->
      path
      |> read()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _number} -> Regex.match?(regex, line) end)
      |> Enum.map(fn {line, number} -> "#{path}:#{number}:#{line}" end)
    end)
  end

  defp sources(root, extension) do
    Enum.filter(entries(root), &(Path.extname(&1) == extension))
  end

  defp entries(root) do
    case File.lstat(root) do
      {:ok, %File.Stat{type: :regular}} -> [root]
      {:ok, %File.Stat{type: :directory}} -> walk(root, @excluded_roots)
      _other -> []
    end
  end

  defp walk(directory, excluded) do
    directory
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn entry ->
      path = Path.join(directory, entry)

      if entry in excluded do
        []
      else
        case File.lstat(path) do
          {:ok, %File.Stat{type: :directory}} -> walk(path, [])
          {:ok, %File.Stat{type: :regular}} -> [path]
          _other -> []
        end
      end
    end)
  end

  defp read(path) do
    with {:ok, content} <- File.read(path),
         true <- String.valid?(content),
         false <- String.contains?(content, <<0>>) do
      content
    else
      _other -> ""
    end
  end
end

CheckBoundary.run()
