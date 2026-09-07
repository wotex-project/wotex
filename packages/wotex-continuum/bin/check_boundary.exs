# Verifies the public boundary using Elixir only.
#
#     elixir bin/check_boundary.exs

defmodule CheckBoundary do
  @moduledoc false

  @excluded_roots [".git", "_build", "cover", "deps", "doc"]

  @organization_roots ["/" <> "Users" <> "/", "/" <> "home" <> "/"]
  @runtime ~r/(def start\(|use GenServer|use Supervisor|Application\.(get|fetch)_env|Ecto\.Repo|use Phoenix|use Oban)/

  def run do
    Enum.each(@organization_roots, fn root ->
      unless containing(".", &String.contains?(&1, root)) == [] do
        abort("organization-internal path detected")
      end
    end)

    unless containing("lib", &Regex.match?(@runtime, &1)) == [] do
      abort("forbidden runtime or framework boundary detected")
    end

    IO.puts("public boundary checks passed")
  end

  defp containing(root, matcher) do
    root
    |> entries()
    |> Enum.filter(&matcher.(read(&1)))
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
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
