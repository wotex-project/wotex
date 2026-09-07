defmodule Wotex.Binding.MQTT.Check.Boundary do
  @moduledoc false

  @framework ~r{(Application\.start\(|use Application|use Ash|use Phoenix|Ecto\.|Oban\.|Plug\.|Bandit\.|Cowboy\.)}
  @process ~r{(GenServer|Supervisor)}
  @client ~r{(Tortoise|EMQX|emqtt|ExMQTT|connection_manager|ConnectionManager)}
  @umbrella ~r{apps_path[[:space:]]*:}
  @consumer_path ~r{([/]Users[/]|[/]home[/])}
  @module ~r{^defmodule }

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

  @spec main([String.t()]) :: :ok
  def main(argv) do
    root = List.first(argv) || "."

    scan(sources(root), @framework, "framework or database boundary violation")
    scan(package(root), @process, "package process boundary violation")
    scan(package(root), @client, "bundled MQTT client or connection manager found")
    scan([path(root, "mix.exs")], @umbrella, "umbrella configuration is forbidden")
    scan([root], @consumer_path, "consumer filesystem path found")

    Enum.each(source_files(root), &single_module!/1)
    Enum.each(test_files(root), &test_module!/1)

    IO.puts("boundary scan passed")
  end

  defp package(root), do: [path(root, "lib"), path(root, "mix.exs")]

  defp sources(root) do
    tests = path(root, "test")

    if File.dir?(tests), do: package(root) ++ [tests], else: package(root)
  end

  defp source_files(root) do
    root |> path("lib") |> files() |> Enum.filter(&(Path.extname(&1) == ".ex"))
  end

  defp test_files(root) do
    root
    |> path("test")
    |> files()
    |> Enum.filter(&(Path.extname(&1) in [".ex", ".exs"]))
    |> Enum.filter(&(modules(&1) > 0))
  end

  defp single_module!(source) do
    unless modules(source) == 1 do
      abort("source file must contain exactly one module: #{source}")
    end
  end

  defp test_module!(source) do
    unless modules(source) == 1 do
      abort("test file must contain exactly one module: #{source}")
    end

    unless declared_moduledoc?(source) do
      abort("test module must have @moduledoc false followed by a blank line: #{source}")
    end
  end

  defp modules(source) do
    source |> read() |> String.split("\n") |> Enum.count(&Regex.match?(@module, &1))
  end

  defp declared_moduledoc?(source) do
    lines = source |> read() |> String.split("\n")

    lines
    |> Enum.with_index()
    |> Enum.any?(fn {line, index} ->
      String.contains?(line, "@moduledoc false") and Enum.at(lines, index + 1) == ""
    end)
  end

  defp scan(roots, pattern, message) do
    hits = roots |> Enum.flat_map(&files/1) |> Enum.flat_map(&matches(&1, pattern))

    unless hits == [] do
      Enum.each(hits, &IO.puts/1)
      abort(message)
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

  defp read(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _reason} -> ""
    end
  end

  defp matches(path, pattern) do
    content = read(path)

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

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Binding.MQTT.Check.Boundary.main(System.argv())
