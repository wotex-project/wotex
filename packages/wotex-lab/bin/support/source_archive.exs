defmodule Wotex.Lab.Check.SourceArchive do
  @moduledoc false

  @nerves_patterns ~w(.check.exs .credo.exs .formatter.exs .gitignore README.md
                      config/**/* lib/**/* rel/**/* test/**/* mix.exs mix.lock)

  @workbench_patterns ~w(.check.exs .credo.exs .dockerignore .formatter.exs .gitignore Dockerfile
                         README.md .storybook/**/* config/**/* lib/**/*
                         priv/static/**/* priv/seeds.exs priv/seeds/**/* test/**/* mix.exs mix.lock
                         assets/**/* tools/**/* package.json pnpm-lock.yaml pnpm-workspace.yaml
                         biome.jsonc tsconfig.json vite.config.ts)

  @spec nerves_patterns() :: [String.t()]
  def nerves_patterns, do: @nerves_patterns

  @spec workbench_patterns() :: [String.t()]
  def workbench_patterns, do: @workbench_patterns

  @spec create!(Path.t(), [String.t()], Path.t(), boolean()) :: :ok
  def create!(root, patterns, output, compressed? \\ false) do
    root = Path.expand(root)

    entries =
      root
      |> files!(patterns)
      |> Enum.map(fn path ->
        member =
          path
          |> Path.relative_to(root)
          |> String.to_charlist()

        {member, String.to_charlist(path)}
      end)

    options = if compressed?, do: [:compressed], else: []

    case :erl_tar.create(String.to_charlist(output), entries, options) do
      :ok -> :ok
      {:error, reason} -> raise "source artifact failed: #{inspect(reason)}"
    end
  end

  defp files!(root, patterns) do
    files =
      patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1), match_dot: true))
      |> Enum.filter(&File.regular?/1)
      |> Enum.uniq()
      |> Enum.sort()

    if files == [], do: raise("source artifact would be empty")

    Enum.each(files, fn path ->
      relative = Path.relative_to(path, root)

      relative
      |> Path.split()
      |> Enum.reduce(root, fn part, parent ->
        current = Path.join(parent, part)

        if match?({:ok, %File.Stat{type: :symlink}}, File.lstat(current)),
          do: raise("source artifact refuses symlink #{relative}")

        current
      end)
    end)

    files
  end
end
