defmodule Wotex.Lab.Docs.RepositoryOverrides do
  @moduledoc false

  @doc false
  @spec admit(map(), [String.t()], boolean()) :: {:ok, %{String.t() => Path.t()}} | {:error, term()}
  def admit(%{"sources" => sources}, values, offline?)
      when is_list(sources) and is_list(values) and is_boolean(offline?) do
    repositories =
      sources
      |> Enum.map(& &1["repository_url"])
      |> MapSet.new()

    with {:ok, overrides} <- parse(values, repositories),
         :ok <- complete(overrides, repositories, offline?) do
      {:ok, overrides}
    end
  end

  def admit(_, values, offline?),
    do: {:error, {:invalid_documentation_repository_overrides, values, offline?}}

  defp parse(values, repositories) do
    Enum.reduce_while(values, {:ok, %{}}, fn value, {:ok, overrides} ->
      case entry(value, repositories, overrides) do
        {:ok, url, path} -> {:cont, {:ok, Map.put(overrides, url, path)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp entry(value, repositories, overrides) when is_binary(value) do
    with [url, path] <- String.split(value, "=", parts: 2),
         true <- MapSet.member?(repositories, url),
         false <- Map.has_key?(overrides, url),
         path = Path.expand(path),
         true <- Path.type(path) == :absolute and File.dir?(path) do
      {:ok, url, path}
    else
      _ -> {:error, {:invalid_documentation_repository_override, value}}
    end
  end

  defp entry(value, _, _), do: {:error, {:invalid_documentation_repository_override, value}}

  defp complete(_, _, false), do: :ok

  defp complete(overrides, repositories, true) do
    missing =
      repositories
      |> MapSet.difference(MapSet.new(Map.keys(overrides)))
      |> Enum.sort()

    if missing == [], do: :ok, else: {:error, {:missing_documentation_repositories, missing}}
  end
end
