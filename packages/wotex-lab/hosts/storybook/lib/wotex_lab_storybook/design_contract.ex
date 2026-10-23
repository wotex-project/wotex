defmodule WotexLabStorybook.DesignContract do
  @moduledoc "Shared design identities exposed by the qualification host."

  alias Wotex.Lab.Island.Snapshot

  @schema "wotex-design-system-contract/v1"
  @components %{
    "reporting-chart" => "chart",
    "data-grid" => "data-grid",
    "navigation-tabs" => "tabs"
  }
  @max_bytes 65_536

  @doc "Returns the shared production identities and the Wotex theme identity."
  @spec current() :: map()
  def current,
    do: Map.put(Wotex.Lab.DesignSystem.contract(), "schema_version", @schema)

  @doc "Loads a bounded generated fixture from this host's own artifact, without fallback data."
  @spec fixture(String.t(), Path.t()) :: {:ok, Snapshot.t()} | {:error, :invalid_story_fixture}
  def fixture(id, path \\ Application.app_dir(:wotex_lab_storybook, "priv/fixtures/islands.json")) do
    with {:ok, component} <- Map.fetch(@components, id),
         {:ok, %{type: :regular, size: size}} when size <= @max_bytes <- File.lstat(path),
         {:ok, bytes} <- read_bounded(path),
         {:ok, %{} = catalogue} <- JSON.decode(bytes),
         %{} = states <- Map.get(catalogue, component),
         %{} = payload <- Map.get(states, "connected"),
         {:ok, snapshot} <- Snapshot.new(component, "storybook--#{id}", payload),
         {:ok, _} <- Snapshot.encode_inline(snapshot) do
      {:ok, snapshot}
    else
      _ -> {:error, :invalid_story_fixture}
    end
  end

  defp read_bounded(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, @max_bytes + 1)) do
      {:ok, bytes} when is_binary(bytes) and byte_size(bytes) <= @max_bytes -> {:ok, bytes}
      _ -> {:error, :invalid_story_fixture}
    end
  end
end
