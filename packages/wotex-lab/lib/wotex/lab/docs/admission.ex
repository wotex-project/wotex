defmodule Wotex.Lab.Docs.Admission do
  @moduledoc """
  Defines the public source-file boundary for generated documentation.

  Git membership is necessary but not sufficient. Only Markdown and Livebook
  sources under a catalogue root are admitted, and machine-local state,
  generated trees, dependencies, credentials and agent instructions are
  rejected before bytes reach DocShell.
  """

  @blocked_segments ~w(.git .doc_shell_source _build bench clients deps doc hosts native node_modules test tmp target)
  @blocked_names ~w(CLAUDE.md AGENTS.md .env .env.local credentials.json secrets.json)
  @extensions ~w(.md .livemd)

  @doc "Returns whether a tracked source path may enter a public collection."
  @spec public?(Path.t(), [Path.t()]) :: boolean()
  def public?(path, roots) when is_binary(path) and is_list(roots) do
    segments = Path.split(path)

    relative_path?(path) and
      Enum.any?(roots, &inside_root?(path, &1)) and
      Path.extname(path) in @extensions and
      Path.basename(path) not in @blocked_names and
      not Enum.any?(segments, &(&1 in @blocked_segments)) and
      not local_task?(segments) and
      not credential_name?(Path.basename(path))
  end

  def public?(_, _), do: false

  @doc "Filters an immutable inventory without changing its order."
  @spec select([Path.t()], [Path.t()]) :: [Path.t()]
  def select(files, roots), do: Enum.filter(files, &public?(&1, roots))

  defp local_task?(segments) do
    Enum.chunk_every(segments, 3, 1, :discard)
    |> Enum.any?(&(&1 == ["docs", "tasks", "local"]))
  end

  defp credential_name?(name) do
    downcased = String.downcase(name)
    String.contains?(downcased, ["credential", "private-key", "secret-key"])
  end

  defp inside_root?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp relative_path?(path) do
    path != "" and Path.type(path) == :relative and ".." not in Path.split(path) and
      not String.contains?(path, ["\\", <<0>>])
  end
end
