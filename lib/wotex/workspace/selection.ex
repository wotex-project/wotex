defmodule Wotex.Workspace.Selection do
  @moduledoc """
  Resolves the `--all`, `--package NAME` and `--base REF` options that the
  workspace tasks share into a list of package names in topological order.

  `classify/2` keeps the reason each package was selected: packages named
  with `--package` or selected by `--all` are `:changed`; the affected set
  marks each package `:changed` or `:dependent` (see
  `Wotex.Workspace.Affected.classify/3`).
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
          | {:only, Affected.mark() | nil}

  @doc """
  Selects packages: every package with `all: true`, the named packages with
  `packages:`, else the affected set for the changes since `base:`. With
  `only: :changed` (or `:dependent`) the result keeps only packages with
  that mark.
  """
  @spec select(Manifest.t(), [option()]) :: {:ok, [String.t()]} | {:error, String.t()}
  def select(%Manifest{} = manifest, opts \\ []) do
    with {:ok, marked} <- classify(manifest, opts) do
      {:ok, Affected.names(marked, Keyword.get(opts, :only))}
    end
  end

  @doc """
  Like `select/2` but every package carries its mark, `:changed` or
  `:dependent`.
  """
  @spec classify(Manifest.t(), [option()]) ::
          {:ok, [{String.t(), Affected.mark()}]} | {:error, String.t()}
  def classify(%Manifest{} = manifest, opts \\ []) do
    packages = Keyword.get(opts, :packages, [])

    cond do
      Keyword.get(opts, :all, false) ->
        {:ok, mark_changed(Manifest.topological_order(manifest))}

      packages != [] ->
        with {:ok, names} <- named(manifest, packages), do: {:ok, mark_changed(names)}

      true ->
        affected(manifest, opts)
    end
  end

  defp mark_changed(names), do: Enum.map(names, &{&1, :changed})

  defp named(manifest, packages) do
    case Enum.reject(packages, &Manifest.package?(&1, manifest)) do
      [] -> {:ok, Manifest.in_order(packages, manifest)}
      unknown -> {:error, "unknown package(s): #{Enum.join(unknown, ", ")}"}
    end
  end

  defp affected(manifest, opts) do
    root = Keyword.get(opts, :root, Workspace.root())

    with {:ok, paths} <- Affected.changed_paths(Keyword.get(opts, :base), root) do
      {:ok, Affected.classify(manifest, paths, docs: Keyword.get(opts, :docs, false))}
    end
  end
end
