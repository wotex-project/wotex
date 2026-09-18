defmodule Wotex.Workspace.Selection do
  @moduledoc """
  Resolves the `--all`, `--package NAME` and `--base REF` options that the
  workspace tasks share into a list of package names in topological order.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Affected
  alias Wotex.Workspace.Manifest

  @type option ::
          {:all, boolean()}
          | {:packages, [String.t()]}
          | {:base, String.t() | nil}
          | {:docs, boolean()}
          | {:root, Path.t()}

  @doc """
  Selects packages: every package with `all: true`, the named packages with
  `packages:`, else the affected set for the changes since `base:`.
  """
  @spec select(Manifest.t(), [option()]) :: {:ok, [String.t()]} | {:error, String.t()}
  def select(%Manifest{} = manifest, opts \\ []) do
    packages = Keyword.get(opts, :packages, [])

    cond do
      Keyword.get(opts, :all, false) ->
        {:ok, Manifest.topological_order(manifest)}

      packages != [] ->
        named(manifest, packages)

      true ->
        affected(manifest, opts)
    end
  end

  defp named(manifest, packages) do
    case Enum.reject(packages, &Manifest.package?(&1, manifest)) do
      [] -> {:ok, Manifest.in_order(packages, manifest)}
      unknown -> {:error, "unknown package(s): #{Enum.join(unknown, ", ")}"}
    end
  end

  defp affected(manifest, opts) do
    root = Keyword.get(opts, :root, Workspace.root())

    with {:ok, paths} <- Affected.changed_paths(Keyword.get(opts, :base), root) do
      {:ok, Affected.affected(manifest, paths, docs: Keyword.get(opts, :docs, false))}
    end
  end
end
