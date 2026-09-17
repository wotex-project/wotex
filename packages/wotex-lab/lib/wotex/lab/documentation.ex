defmodule Wotex.Lab.Documentation do
  @moduledoc """
  Locates the documentation tree of a Lab source checkout.

  Catalogue paths that start with `docs/` name the package documentation
  tree, not a directory beside `mix.exs`: in a standalone checkout that tree
  is `docs/`, in the monorepo it is `docs/packages/wotex-lab/` two levels
  above the package. The tree holds specifications, the completion plan,
  decisions and provenance reviews for people; data that code reads lives in
  `priv/`. A compiled package or an unpacked archive ships no documentation,
  so the tree may be absent and callers must say so instead of failing.
  """

  @package "wotex-lab"
  @kinds ~w(specs plans decisions provenance)

  @doc "The documentation kinds the tree is organised by."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc """
  The documentation directory of the checkout at `root`, or `:error` when the
  checkout ships none.
  """
  @spec directory(Path.t()) :: {:ok, Path.t()} | :error
  def directory(root) when is_binary(root) do
    [Path.join(root, "docs"), Path.expand("../../docs/packages/#{@package}", root)]
    |> Enum.find(&File.dir?(Path.join(&1, "specs")))
    |> case do
      nil -> :error
      directory -> {:ok, directory}
    end
  end

  @doc """
  Expands a catalogue path against the checkout at `root`.

  `docs/…` paths resolve inside the documentation tree, every other path
  inside the package. Returns `:error` when the path escapes its base or the
  documentation tree is absent; the file itself is not checked.
  """
  @spec resolve(Path.t(), String.t()) :: {:ok, Path.t()} | :error
  def resolve(root, "docs/" <> relative) do
    with {:ok, directory} <- directory(root), do: contained(directory, relative)
  end

  def resolve(root, path) when is_binary(root) and is_binary(path), do: contained(root, path)

  defp contained(base, path) do
    base = Path.expand(base)
    candidate = Path.expand(path, base)
    if String.starts_with?(candidate, base <> "/"), do: {:ok, candidate}, else: :error
  end
end
