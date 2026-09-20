defmodule Wotex.Workspace.NativeArtifact.Planner do
  @moduledoc "Pure change-to-cell planning for the closed native artifact inventory."

  alias Wotex.Workspace.Affected
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Descriptor

  @type cell :: %{
          package: String.t(),
          profile: String.t(),
          target: String.t(),
          toolchain: String.t(),
          system: String.t(),
          status: :supported | :unsupported,
          reason: String.t() | nil
        }

  @type plan :: %{
          cells: [cell()],
          slices: [[cell()]],
          fallback: boolean(),
          fallback_reason: String.t() | nil
        }

  @doc "Expands every descriptor target into deterministic qualification cells."
  @spec cells([Descriptor.t()], Manifest.t()) :: [cell()]
  def cells(descriptors, %Manifest{} = manifest) do
    descriptors
    |> Enum.flat_map(fn descriptor ->
      Enum.map(descriptor.targets, fn support ->
        target = Map.fetch!(manifest.native_artifact.targets, support.name)

        %{
          package: descriptor.package,
          profile: descriptor.profile,
          target: target.name,
          toolchain: target.toolchain,
          system: target.system,
          status: support.status,
          reason: support.reason
        }
      end)
    end)
    |> Enum.sort_by(&cell_key/1)
  end

  @doc "Selects cells using explicit paths and the existing affected-package graph."
  @spec select([cell()], Manifest.t(), [Path.t()], keyword()) :: [cell()]
  def select(cells, %Manifest{} = manifest, changed_paths, opts \\ []) do
    cond do
      Keyword.get(opts, :all, false) ->
        filter_packages(cells, opts)

      Keyword.get(opts, :packages, []) != [] ->
        filter_packages(cells, opts)

      Keyword.get(opts, :fallback, false) ->
        smoke = smoke_cells(cells, manifest)
        filter_packages(smoke, opts)

      "tooling/packages.yaml" in changed_paths ->
        filter_packages(cells, opts)

      true ->
        selected =
          MapSet.new()
          |> select_package_cells(cells, manifest, changed_paths)
          |> select_root_input_cells(cells, manifest, changed_paths)
          |> select_smoke_for_tooling(cells, manifest, changed_paths)

        cells
        |> Enum.filter(&MapSet.member?(selected, cell_key(&1)))
        |> filter_packages(opts)
    end
  end

  @doc "Builds a bounded, semantically sliced plan."
  @spec plan([Descriptor.t()], Manifest.t(), [Path.t()], keyword()) ::
          {:ok, plan()} | {:error, String.t()}
  def plan(descriptors, %Manifest{} = manifest, changed_paths, opts \\ []) do
    limit = Keyword.get(opts, :limit, manifest.native_artifact.matrix_limit)
    max_slices = manifest.native_artifact.max_slices

    with :ok <- validate_limit(limit),
         selected <- select(cells(descriptors, manifest), manifest, changed_paths, opts),
         slices <- slice(selected, limit),
         :ok <- validate_expansion(slices, max_slices) do
      fallback = Keyword.get(opts, :fallback, false)

      {:ok,
       %{
         cells: selected,
         slices: slices,
         fallback: fallback,
         fallback_reason:
           if(fallback, do: Keyword.get(opts, :fallback_reason, "diff unavailable"), else: nil)
       }}
    end
  end

  @doc "Splits cells first by target/system identity and then by the executor limit."
  @spec slice([cell()], pos_integer()) :: [[cell()]]
  def slice(cells, limit) do
    cells
    |> Enum.group_by(&{&1.target, &1.system})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {_, boundary_cells} ->
      boundary_cells
      |> Enum.sort_by(&cell_key/1)
      |> Enum.chunk_every(limit)
    end)
  end

  defp select_package_cells(selected, cells, manifest, changed_paths) do
    package_paths = Enum.filter(changed_paths, &String.starts_with?(&1, "packages/"))
    affected = MapSet.new(Affected.affected(manifest, package_paths))

    Enum.reduce(cells, selected, fn cell, acc ->
      if MapSet.member?(affected, cell.package), do: MapSet.put(acc, cell_key(cell)), else: acc
    end)
  end

  defp select_root_input_cells(selected, cells, manifest, changed_paths) do
    changed = MapSet.new(changed_paths)

    Enum.reduce(cells, selected, fn cell, acc ->
      target = Map.fetch!(manifest.native_artifact.targets, cell.target)
      toolchain = Map.fetch!(manifest.native_artifact.toolchains, target.toolchain)
      system = Map.fetch!(manifest.native_artifact.systems, target.system)

      if Enum.any?(toolchain.inputs ++ system.inputs, &MapSet.member?(changed, &1)),
        do: MapSet.put(acc, cell_key(cell)),
        else: acc
    end)
  end

  defp select_smoke_for_tooling(selected, cells, manifest, changed_paths) do
    if Enum.any?(changed_paths, &native_tooling?/1) do
      Enum.reduce(smoke_cells(cells, manifest), selected, &MapSet.put(&2, cell_key(&1)))
    else
      selected
    end
  end

  defp native_tooling?(path) do
    String.starts_with?(path, "lib/wotex/workspace/native_artifact/") or
      String.starts_with?(path, "lib/mix/tasks/wotex.native.") or
      path in ["lib/wotex/workspace/manifest.ex", "lib/wotex/workspace/native.ex"]
  end

  defp smoke_cells(cells, manifest) do
    smoke = MapSet.new(manifest.native_artifact.smoke, &{&1.package, &1.profile, &1.target})
    Enum.filter(cells, &MapSet.member?(smoke, {&1.package, &1.profile, &1.target}))
  end

  defp filter_packages(cells, opts) do
    case Keyword.get(opts, :packages, []) do
      [] -> cells
      packages -> Enum.filter(cells, &(&1.package in packages))
    end
  end

  defp validate_limit(limit) when is_integer(limit) and limit > 0 and limit <= 256, do: :ok
  defp validate_limit(_), do: {:error, "matrix limit must be an integer from 1 through 256"}

  defp validate_expansion(slices, max_slices) do
    if length(slices) <= max_slices,
      do: :ok,
      else:
        {:error,
         "native matrix needs #{length(slices)} slices; configured maximum is #{max_slices}"}
  end

  defp cell_key(cell), do: {cell.package, cell.profile, cell.target, cell.toolchain, cell.system}
end
