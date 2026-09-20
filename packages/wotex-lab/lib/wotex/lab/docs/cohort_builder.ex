defmodule Wotex.Lab.Docs.CohortBuilder do
  @moduledoc """
  Builds the closed documentation cohort without sharing dependency state.

  Each source is cloned and built through `CollectionBuilder` in its own lane.
  Only validated portable artifacts cross back into the aggregate process. The
  caller owns the new workspace and can publish it only after projection,
  rendering and the remaining site gates succeed.
  """

  alias Wotex.Lab.Docs.{Catalogue, CollectionBuilder, CommandEnvironment}

  @compile {:no_warn_undefined, DocShell.Generate.Cohort}

  @allowed_options [:repository_overrides, :locked]

  @typedoc "An ordered validated source cohort and its portable identity."
  @type built :: %{
          catalogue: Catalogue.t(),
          collections: [map()],
          collection_paths: %{String.t() => Path.t()},
          cohort: struct() | nil,
          workspace: Path.t()
        }

  @doc "Builds all source collections and constructs the candidate DocShell cohort."
  @spec build(Catalogue.t(), Path.t(), keyword()) :: {:ok, built()} | {:error, term()}
  def build(catalogue, workspace, opts \\ []) do
    with {:ok, result} <- build_collections(catalogue, workspace, opts),
         {:ok, cohort} <- doc_shell_cohort(result.collections, catalogue["profile"]) do
      {:ok, %{result | cohort: cohort}}
    end
  end

  @doc "Builds and imports every collection without requiring site-projection APIs."
  @spec build_collections(Catalogue.t(), Path.t(), keyword()) ::
          {:ok, built()} | {:error, term()}
  def build_collections(catalogue, workspace, opts \\ []) do
    with :ok <- validate_options(opts),
         :ok <- validate_catalogue(catalogue, Keyword.get(opts, :locked, true)),
         :ok <- validate_workspace(workspace),
         {:ok, workspace} <- canonical_workspace(workspace),
         :ok <- File.mkdir(workspace),
         {:ok, collector} <- collector_source(catalogue),
         {:ok, collections, paths} <-
           build_sources(
             catalogue,
             collector,
             workspace,
             Keyword.get(opts, :repository_overrides, %{})
           ) do
      {:ok,
       %{
         catalogue: catalogue,
         collections: collections,
         collection_paths: paths,
         cohort: nil,
         workspace: workspace
       }}
    end
  end

  defp validate_options(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- @allowed_options == [] do
      cond do
        not is_boolean(Keyword.get(opts, :locked, true)) ->
          {:error, {:invalid_cohort_lock_option, Keyword.get(opts, :locked)}}

        not valid_overrides?(Keyword.get(opts, :repository_overrides, %{})) ->
          {:error, {:invalid_repository_overrides, Keyword.get(opts, :repository_overrides)}}

        true ->
          :ok
      end
    else
      {:error, {:invalid_cohort_builder_options, opts}}
    end
  end

  defp validate_catalogue(catalogue, true), do: Catalogue.validate_locked(catalogue)
  defp validate_catalogue(catalogue, false), do: Catalogue.validate(catalogue)

  defp validate_workspace(workspace) do
    cond do
      not is_binary(workspace) or Path.type(workspace) != :absolute ->
        {:error, {:invalid_cohort_workspace, workspace}}

      File.exists?(workspace) ->
        {:error, {:occupied_cohort_workspace, workspace}}

      not File.dir?(Path.dirname(workspace)) ->
        {:error, {:missing_cohort_workspace_parent, Path.dirname(workspace)}}

      true ->
        :ok
    end
  end

  defp canonical_workspace(workspace) do
    case System.cmd("pwd", ["-P"],
           cd: Path.dirname(workspace),
           stderr_to_stdout: true,
           env: CommandEnvironment.scrubbed()
         ) do
      {output, 0} -> {:ok, Path.join(String.trim(output), Path.basename(workspace))}
      {output, status} -> {:error, {:canonical_workspace_failed, status, tail(output)}}
    end
  end

  defp collector_source(catalogue) do
    case Catalogue.fetch(catalogue, "family-docs") do
      {:ok, source} -> {:ok, Map.take(source, ["repository_url", "revision"])}
      :error -> {:error, :missing_documentation_collector_source}
    end
  end

  defp build_sources(catalogue, collector, workspace, overrides) do
    result =
      Enum.reduce_while(catalogue["sources"], {:ok, [], %{}}, fn source,
                                                                 {:ok, collections, paths} ->
        case build_source(source, collector, workspace, overrides) do
          {:ok, collection, path} ->
            {:cont, {:ok, [collection | collections], Map.put(paths, source["id"], path)}}

          {:error, reason} ->
            {:halt, {:error, {:documentation_source_failed, source["id"], reason}}}
        end
      end)

    case result do
      {:ok, collections, paths} -> {:ok, Enum.reverse(collections), paths}
      error -> error
    end
  end

  defp build_source(source, collector, workspace, overrides) do
    lane = Path.join([workspace, "lanes", source["id"]])
    repository = override(overrides, source)
    collector_repository = override(overrides, collector)

    opts =
      [collector: collector]
      |> optional(:repository, repository)
      |> optional(:collector_repository, collector_repository)

    with :ok <- File.mkdir_p(Path.dirname(lane)),
         {:ok, built} <- CollectionBuilder.build(source, lane, opts),
         target = Path.join([workspace, "collections", source["id"]]),
         :ok <- copy_artifacts(Path.dirname(built.artifact_dir), target),
         public = Path.join(target, "public"),
         descriptor = %{built.collection.descriptor | artifact_dir: public},
         {:ok, imported} <- DocShell.Generate.Collection.load(descriptor),
         true <- imported.content_digest == built.collection.content_digest do
      {:ok, imported, public}
    else
      false -> {:error, :copied_collection_digest_mismatch}
      {:error, _} = error -> error
    end
  end

  defp copy_artifacts(source, destination) do
    with false <- File.exists?(destination),
         :ok <- File.mkdir_p(Path.dirname(destination)),
         {:ok, _} <- File.cp_r(source, destination) do
      :ok
    else
      true ->
        {:error, {:occupied_collection_destination, destination}}

      {:error, reason} ->
        {:error, {:collection_destination_parent_failed, Path.dirname(destination), reason}}

      {:error, reason, path} ->
        {:error, {:copy_collection_failed, path, reason}}
    end
  end

  defp doc_shell_cohort(collections, profile) do
    module = DocShell.Generate.Cohort

    if Code.ensure_loaded?(module) and function_exported?(module, :new, 2),
      do: DocShell.Generate.Cohort.new(collections, profile),
      else: {:error, :doc_shell_site_candidate_required}
  end

  defp valid_overrides?(overrides) when is_map(overrides) do
    Enum.all?(overrides, fn {key, path} ->
      is_binary(key) and key != "" and is_binary(path) and Path.type(path) == :absolute and
        File.dir?(path)
    end)
  end

  defp valid_overrides?(_), do: false

  defp override(overrides, source) do
    Map.get(overrides, source["id"]) || Map.get(overrides, source["repository_url"])
  end

  defp optional(opts, _, nil), do: opts
  defp optional(opts, key, value), do: Keyword.put(opts, key, value)

  defp tail(output) do
    output
    |> String.slice(-8_192, 8_192)
    |> String.trim()
  end
end
