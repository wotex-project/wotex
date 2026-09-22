defmodule WotexLabWorkbench.Documentation.Publication do
  @moduledoc """
  Builds and atomically activates one documentation and Storybook publication.

  Both producers write to private sibling staging trees. Their manifests,
  routes and files are validated before the destination is touched. Replacing
  an existing publication uses a same-filesystem backup and rollback boundary,
  so a failed producer or preflight leaves the preceding complete tree intact.
  """

  alias WotexLabWorkbench.Documentation.{Build, CommandEnvironment, StorybookBuilder}

  @schema "wotex-documentation-publication/v1"
  @manifest "publication-manifest.json"

  @allowed_options ~w(destination base_path canonical_origin generation_id
                      pagefind_executable generated_at storybook_source
                      storybook_artifact)a

  @doc "Builds both static trees and activates them together."
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%{catalogue: _, collections: _} = cohort, opts) when is_list(opts) do
    with :ok <- validate_run_options(opts),
         {:ok, destination} <- destination(Keyword.get(opts, :destination)),
         {:ok, base_path, storybook_base} <- paths(Keyword.get(opts, :base_path, "/docs/")),
         {:ok, workspace} <- workspace(Path.dirname(destination)) do
      try do
        build_and_publish(cohort, destination, workspace, base_path, storybook_base, opts)
      after
        File.rm_rf(workspace)
      end
    end
  end

  def run(value, opts), do: {:error, {:invalid_documentation_publication, value, opts}}

  @doc "Combines two already built trees and activates the result atomically."
  @spec publish(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def publish(%{documentation: docs, storybook: storybook}, opts)
      when is_binary(docs) and is_binary(storybook) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         true <- Keyword.keys(opts) -- [:destination, :base_path] == [],
         {:ok, destination} <- destination(Keyword.get(opts, :destination)),
         {:ok, base_path, storybook_base} <- paths(Keyword.get(opts, :base_path, "/docs/")),
         {:ok, workspace} <- workspace(Path.dirname(destination)) do
      try do
        combine_and_activate(docs, storybook, destination, workspace, base_path, storybook_base)
      after
        File.rm_rf(workspace)
      end
    else
      false -> {:error, {:invalid_documentation_publish_options, opts}}
      {:error, _} = error -> error
    end
  end

  def publish(value, opts), do: {:error, {:invalid_documentation_publication_trees, value, opts}}

  defp build_and_publish(cohort, destination, workspace, base_path, storybook_base, opts) do
    docs_destination = Path.join(workspace, "documentation")
    storybook_destination = Path.join(workspace, "storybook")

    docs_options =
      [destination: docs_destination, base_path: base_path]
      |> optional(:canonical_origin, Keyword.get(opts, :canonical_origin))
      |> optional(:generation_id, Keyword.get(opts, :generation_id))
      |> optional(:pagefind_executable, Keyword.get(opts, :pagefind_executable))
      |> optional(:generated_at, Keyword.get(opts, :generated_at))

    storybook_options =
      [destination: storybook_destination, base_path: storybook_base]
      |> optional(:source, Keyword.get(opts, :storybook_source))
      |> optional(:artifact, Keyword.get(opts, :storybook_artifact))

    with {:ok, docs} <- Build.run(cohort, docs_options),
         {:ok, storybook} <- StorybookBuilder.run(storybook_options),
         {:ok, published} <-
           combine_and_activate(
             docs.destination,
             storybook.destination,
             destination,
             workspace,
             base_path,
             storybook_base
           ) do
      {:ok, Map.merge(published, %{documentation: docs, storybook: storybook})}
    end
  end

  defp combine_and_activate(
         docs,
         storybook,
         destination,
         workspace,
         base_path,
         storybook_base
       ) do
    stage = Path.join(workspace, "publication")
    storybook_relative = String.trim(storybook_base, "/")

    with {:ok, docs_files} <- tree(docs),
         {:ok, storybook_files} <- tree(storybook),
         {:ok, docs_manifest} <- manifest(docs, "site-manifest.json"),
         {:ok, storybook_manifest} <- manifest(storybook, "storybook-manifest.json"),
         :ok <- validate_manifests(docs_manifest, storybook_manifest, base_path, storybook_base),
         :ok <- no_collisions(docs_files, storybook_files, storybook_relative),
         {:ok, _} <- File.cp_r(docs, stage),
         storybook_target = Path.join(stage, storybook_relative),
         :ok <- File.mkdir_p(Path.dirname(storybook_target)),
         {:ok, _} <- File.cp_r(storybook, storybook_target),
         {:ok, combined_files} <- tree(stage),
         {:ok, output_digest} <- tree_digest(stage, combined_files),
         publication_manifest =
           publication_manifest(
             docs_manifest,
             storybook_manifest,
             base_path,
             storybook_base,
             output_digest,
             length(combined_files)
           ),
         :ok <- write_manifest(stage, publication_manifest),
         :ok <- activate(stage, destination) do
      {:ok,
       %{
         destination: destination,
         manifest: publication_manifest,
         documentation_manifest: docs_manifest,
         storybook_manifest: storybook_manifest
       }}
    else
      {:error, reason, path} -> {:error, {:documentation_publication_copy_failed, path, reason}}
      {:error, _} = error -> error
    end
  end

  defp validate_run_options(opts) do
    producers =
      Enum.count(
        [Keyword.get(opts, :storybook_source), Keyword.get(opts, :storybook_artifact)],
        &is_binary/1
      )

    if Keyword.keyword?(opts) and Keyword.keys(opts) -- @allowed_options == [] and producers == 1,
      do: :ok,
      else: {:error, {:invalid_documentation_publication_options, opts}}
  end

  defp destination(path) do
    cond do
      not is_binary(path) or Path.type(path) != :absolute ->
        {:error, {:invalid_documentation_publication_destination, path}}

      not File.dir?(Path.dirname(path)) ->
        {:error, {:missing_documentation_publication_parent, Path.dirname(path)}}

      File.exists?(path) and not File.dir?(path) ->
        {:error, {:invalid_existing_documentation_publication, path}}

      true ->
        case System.cmd("pwd", ["-P"],
               cd: Path.dirname(path),
               env: CommandEnvironment.cleared(),
               stderr_to_stdout: true
             ) do
          {output, 0} -> {:ok, Path.join(String.trim(output), Path.basename(path))}
          {output, status} -> {:error, {:canonical_publication_path_failed, status, tail(output)}}
        end
    end
  end

  defp paths(base_path) when is_binary(base_path) do
    if Regex.match?(~r|\A/(?:[a-zA-Z0-9._~-]+/)*docs/\z|, base_path) do
      segments = Path.split(String.trim(base_path, "/"))
      prefix = Enum.drop(segments, -1)
      storybook = "/" <> Enum.join(Enum.concat(prefix, ["design-system"]), "/") <> "/"
      {:ok, base_path, storybook}
    else
      {:error, {:invalid_documentation_publication_base, base_path}}
    end
  end

  defp paths(base_path), do: {:error, {:invalid_documentation_publication_base, base_path}}

  defp workspace(parent) do
    path = Path.join(parent, ".wotex-documentation-stage-#{token()}")

    case File.mkdir(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:documentation_publication_stage_failed, path, reason}}
    end
  end

  defp tree(root) when is_binary(root) do
    if File.dir?(root), do: walk(root, root), else: {:error, {:missing_publication_tree, root}}
  end

  defp walk(root, directory) do
    with {:ok, names} <- File.ls(directory) do
      names
      |> Enum.sort()
      |> Enum.reduce_while({:ok, []}, fn name, {:ok, files} ->
        path = Path.join(directory, name)

        case File.lstat(path) do
          {:ok, %{type: :regular}} ->
            {:cont, {:ok, [Path.relative_to(path, root) | files]}}

          {:ok, %{type: :directory}} ->
            merge_directory(root, path, files)

          {:ok, %{type: type}} ->
            {:halt, {:error, {:forbidden_publication_entry, Path.relative_to(path, root), type}}}

          {:error, reason} ->
            {:halt, {:error, {:publication_entry_unreadable, path, reason}}}
        end
      end)
      |> then(fn
        {:ok, files} -> {:ok, Enum.sort(files)}
        error -> error
      end)
    end
  end

  defp merge_directory(root, path, files) do
    case walk(root, path) do
      {:ok, nested} -> {:cont, {:ok, nested ++ files}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp manifest(root, name) do
    path = Path.join(root, name)

    with {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size <= 4_194_304,
         {:ok, bytes} <- File.read(path),
         {:ok, value} <- JSON.decode(bytes),
         true <- is_map(value) do
      {:ok, value}
    else
      false -> {:error, {:invalid_publication_manifest, name}}
      {:error, reason} -> {:error, {:invalid_publication_manifest, name, reason}}
      _ -> {:error, {:invalid_publication_manifest, name}}
    end
  end

  defp validate_manifests(docs, storybook, base_path, storybook_base) do
    cond do
      docs["base_path"] != base_path ->
        {:error, {:documentation_manifest_base_mismatch, docs["base_path"], base_path}}

      storybook["schema_version"] != "wotex-storybook-artifact/v1" ->
        {:error, :invalid_storybook_publication_manifest}

      storybook["base_path"] != storybook_base ->
        {:error, {:storybook_manifest_base_mismatch, storybook["base_path"], storybook_base}}

      true ->
        :ok
    end
  end

  defp no_collisions(docs_files, storybook_files, storybook_relative) do
    docs = MapSet.new(docs_files)

    collisions =
      storybook_files
      |> Enum.map(&Path.join(storybook_relative, &1))
      |> Enum.filter(&MapSet.member?(docs, &1))

    cond do
      @manifest in docs_files -> {:error, {:publication_manifest_collision, @manifest}}
      collisions != [] -> {:error, {:documentation_storybook_collision, Enum.sort(collisions)}}
      true -> :ok
    end
  end

  defp publication_manifest(
         docs,
         storybook,
         base_path,
         storybook_base,
         output_digest,
         file_count
       ) do
    %{
      "schema_version" => @schema,
      "documentation_base_path" => base_path,
      "storybook_base_path" => storybook_base,
      "cohort_digest" => docs["cohort_digest"],
      "documentation_manifest_digest" => canonical_digest(docs),
      "storybook_manifest_digest" => canonical_digest(storybook),
      "design_system" => storybook["design_system"],
      "output_digest_algorithm" => "sha256-path-nul-content-v1",
      "output_digest" => output_digest,
      "file_count" => file_count
    }
  end

  defp canonical_digest(value) do
    {:ok, digest} = DocShell.Json.Canonical.digest(value)
    digest
  end

  defp write_manifest(stage, manifest) do
    with {:ok, bytes} <- DocShell.Json.Canonical.encode(manifest) do
      File.write(Path.join(stage, @manifest), bytes, [:binary, :exclusive, :sync])
    end
  end

  defp tree_digest(root, files) do
    result =
      Enum.reduce_while(files, {:ok, :crypto.hash_init(:sha256)}, fn relative, {:ok, state} ->
        case File.read(Path.join(root, relative)) do
          {:ok, bytes} ->
            {:cont, {:ok, :crypto.hash_update(state, [relative, <<0>>, bytes, <<0>>])}}

          {:error, reason} ->
            {:halt, {:error, {:publication_digest_failed, relative, reason}}}
        end
      end)

    with {:ok, state} <- result do
      {:ok, "sha256:" <> Base.encode16(:crypto.hash_final(state), case: :lower)}
    end
  end

  defp activate(stage, destination) do
    if File.exists?(destination),
      do: replace(stage, destination),
      else: File.rename(stage, destination)
  end

  defp replace(stage, destination) do
    backup = destination <> ".previous-#{token()}"

    with :ok <- File.rename(destination, backup) do
      case File.rename(stage, destination) do
        :ok ->
          case File.rm_rf(backup) do
            {:ok, _} -> :ok
            {:error, reason, path} -> {:error, {:publication_backup_cleanup_failed, path, reason}}
          end

        {:error, reason} ->
          rollback = File.rename(backup, destination)
          {:error, {:documentation_publication_activation_failed, reason, rollback}}
      end
    end
  end

  defp optional(opts, _, nil), do: opts
  defp optional(opts, key, value), do: Keyword.put(opts, key, value)
  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  defp tail(output), do: String.trim(String.slice(output, -8_192, 8_192))
end
