defmodule WotexLabWorkbench.Documentation.StorybookBuilder do
  @moduledoc """
  Builds or adopts Wotex Lab's production Svelte Storybook as a closed tree.

  Source builds execute the pinned Storybook binary from the Workbench asset
  workspace and import its production components and island stories. Adopted
  artifacts must carry the same self-verifying manifest. Neither path permits
  symlinks, source maps, remote runtime assets or an unbounded output tree.
  """

  alias WotexLabWorkbench.Documentation.{CommandEnvironment, DesignContract}

  @schema "wotex-storybook-artifact/v1"
  @manifest "storybook-manifest.json"
  @maximum_file_bytes 4 * 1_024 * 1_024
  @maximum_tree_bytes 20 * 1_024 * 1_024
  @allowed_options ~w(destination base_path source artifact)a

  @doc "Builds from `:source` or adopts `:artifact` into a new destination."
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) when is_list(opts) do
    with :ok <- validate_options(opts),
         {:ok, destination} <- destination(Keyword.get(opts, :destination)),
         {:ok, base_path} <- base_path(Keyword.get(opts, :base_path)) do
      produce(opts, destination, base_path)
    end
  end

  def run(opts), do: {:error, {:invalid_storybook_options, opts}}

  defp validate_options(opts) do
    sources = Enum.count([Keyword.get(opts, :source), Keyword.get(opts, :artifact)], &is_binary/1)

    if Keyword.keyword?(opts) and Keyword.keys(opts) -- @allowed_options == [] and sources == 1,
      do: :ok,
      else: {:error, {:invalid_storybook_options, opts}}
  end

  defp destination(path) do
    cond do
      not is_binary(path) or Path.type(path) != :absolute ->
        {:error, {:invalid_storybook_destination, path}}

      File.exists?(path) ->
        {:error, {:occupied_storybook_destination, path}}

      not File.dir?(Path.dirname(path)) ->
        {:error, {:missing_storybook_parent, Path.dirname(path)}}

      true ->
        canonical_new_path(path)
    end
  end

  defp base_path(path) when is_binary(path) do
    if Regex.match?(~r|\A/(?:[a-zA-Z0-9._~-]+/)*\z|, path),
      do: {:ok, path},
      else: {:error, {:invalid_storybook_base_path, path}}
  end

  defp base_path(path), do: {:error, {:invalid_storybook_base_path, path}}

  defp produce(opts, destination, base_path) do
    case {Keyword.get(opts, :source), Keyword.get(opts, :artifact)} do
      {source, nil} -> build(source, destination, base_path)
      {nil, artifact} -> adopt(artifact, destination, base_path)
    end
  end

  defp build(source, destination, base_path) do
    with {:ok, source} <- source_root(source),
         {:ok, package} <- package(source),
         :ok <- compatible_version(package),
         {:ok, contract} <- DesignContract.current(),
         :ok <- execute(source, destination, base_path),
         {:ok, files} <- validate_tree(destination),
         {:ok, story_count} <- story_count(destination),
         {:ok, output_digest} <- tree_digest(destination, files),
         {:ok, revision} <- source_revision(source),
         manifest =
           manifest(
             base_path,
             package,
             contract,
             story_count,
             length(files),
             output_digest,
             revision
           ),
         :ok <- write_manifest(destination, manifest) do
      {:ok, %{destination: destination, manifest: manifest}}
    end
  end

  defp adopt(artifact, destination, base_path) do
    with {:ok, artifact} <- existing_directory(artifact, :storybook_artifact),
         {:ok, manifest} <- read_manifest(artifact),
         :ok <- validate_manifest(manifest, base_path),
         {:ok, files} <- validate_tree(artifact),
         {:ok, digest} <- tree_digest(artifact, List.delete(files, @manifest)),
         true <- digest == manifest["output_digest"],
         {:ok, _} <- File.cp_r(artifact, destination) do
      {:ok, %{destination: destination, manifest: manifest}}
    else
      false -> {:error, :storybook_artifact_digest_mismatch}
      {:error, reason, path} -> {:error, {:storybook_artifact_copy_failed, path, reason}}
      {:error, _} = error -> error
    end
  end

  defp source_root(path) do
    with {:ok, root} <- existing_directory(path, :storybook_source),
         true <- File.regular?(Path.join(root, "package.json")),
         true <- File.regular?(Path.join(root, ".storybook/main.ts")),
         true <- File.regular?(Path.join(root, "node_modules/.bin/storybook")) do
      {:ok, root}
    else
      false -> {:error, {:invalid_storybook_source, path}}
      {:error, _} = error -> error
    end
  end

  defp existing_directory(path, context) do
    cond do
      not is_binary(path) or Path.type(path) != :absolute ->
        {:error, {:invalid_storybook_path, context, path}}

      not File.dir?(path) ->
        {:error, {:missing_storybook_path, context, path}}

      true ->
        case System.cmd("pwd", ["-P"],
               cd: path,
               env: CommandEnvironment.cleared(),
               stderr_to_stdout: true
             ) do
          {output, 0} -> {:ok, String.trim(output)}
          {output, status} -> {:error, {:canonical_storybook_path_failed, status, tail(output)}}
        end
    end
  end

  defp canonical_new_path(path) do
    case System.cmd("pwd", ["-P"],
           cd: Path.dirname(path),
           env: CommandEnvironment.cleared(),
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, Path.join(String.trim(output), Path.basename(path))}
      {output, status} -> {:error, {:canonical_storybook_path_failed, status, tail(output)}}
    end
  end

  defp package(source) do
    path = Path.join(source, "package.json")

    with {:ok, bytes} <- File.read(path),
         {:ok, %{"version" => version, "devDependencies" => dependencies} = package} <-
           JSON.decode(bytes),
         true <- is_binary(version) and is_map(dependencies),
         storybook when is_binary(storybook) <- dependencies["storybook"] do
      {:ok, Map.take(package, ["name", "version"]) |> Map.put("storybook_version", storybook)}
    else
      false -> {:error, :invalid_storybook_package}
      nil -> {:error, :missing_storybook_version}
      {:error, reason} -> {:error, {:invalid_storybook_package, reason}}
      _ -> {:error, :invalid_storybook_package}
    end
  end

  defp compatible_version(%{"version" => version}) do
    if version == WotexLabWorkbench.version(),
      do: :ok,
      else: {:error, {:workbench_npm_version_mismatch, WotexLabWorkbench.version(), version}}
  end

  defp execute(source, destination, base_path) do
    executable = Path.join(source, "node_modules/.bin/storybook")
    args = ["build", "--quiet", "--output-dir", destination]

    case System.cmd(executable, args,
           cd: source,
           env: CommandEnvironment.cleared([{"WOTEX_LAB_STORYBOOK_BASE", base_path}]),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {output, status} -> {:error, {:storybook_build_failed, status, tail(output)}}
    end
  rescue
    error in ErlangError -> {:error, {:storybook_build_start_failed, error.original}}
  end

  defp validate_tree(root) do
    with {:ok, files} <- walk(root, root),
         true <- files != [],
         true <- Enum.all?(~w(index.html iframe.html index.json), &(&1 in files)),
         :ok <- validate_files(root, files) do
      {:ok, files}
    else
      false -> {:error, :incomplete_storybook_tree}
      {:error, _} = error -> error
    end
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
            {:halt, {:error, {:forbidden_storybook_entry, Path.relative_to(path, root), type}}}

          {:error, reason} ->
            {:halt, {:error, {:storybook_entry_unreadable, path, reason}}}
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

  defp validate_files(root, files) do
    result =
      Enum.reduce_while(files, {:ok, 0}, fn relative, {:ok, total} ->
        path = Path.join(root, relative)

        with {:ok, stat} <- File.stat(path),
             true <- stat.size <= @maximum_file_bytes,
             true <- total + stat.size <= @maximum_tree_bytes,
             {:ok, bytes} <- File.read(path),
             :ok <- no_source_map(relative, bytes),
             :ok <- local_runtime(relative, bytes) do
          {:cont, {:ok, total + stat.size}}
        else
          false -> {:halt, {:error, {:storybook_asset_budget, relative}}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp local_runtime(relative, bytes) do
    violation =
      cond do
        String.ends_with?(relative, ".html") ->
          Regex.match?(
            ~r/<(?:script|img|iframe|source|video|audio)\b[^>]*\bsrc\s*=\s*["']https?:\/\//i,
            bytes
          ) or remote_link_asset?(bytes)

        String.ends_with?(relative, ".css") ->
          Regex.match?(~r/(?:@import\s+|url\()["']?https?:\/\//i, bytes)

        String.ends_with?(relative, [".js", ".mjs"]) ->
          String.contains?(bytes, "sourceMappingURL=") or
            Regex.match?(~r/(?:fetch|import)\s*\(\s*["']https?:\/\//i, bytes) or
            Regex.match?(~r/new\s+WebSocket\s*\(\s*["']wss?:\/\//i, bytes)

        true ->
          false
      end

    if violation,
      do: {:error, {:remote_or_mapped_storybook_runtime, relative}},
      else: :ok
  end

  defp no_source_map(relative, bytes) do
    if String.ends_with?(relative, ".map") or String.contains?(bytes, "sourceMappingURL="),
      do: {:error, {:storybook_source_map, relative}},
      else: :ok
  end

  defp remote_link_asset?(html) do
    html
    |> then(&Regex.scan(~r/<link\b[^>]*>/i, &1))
    |> Enum.any?(fn [tag] ->
      Regex.match?(~r/href\s*=\s*["']https?:\/\//i, tag) and
        Regex.match?(~r/rel\s*=\s*["'][^"']*(?:stylesheet|modulepreload|preload)/i, tag)
    end)
  end

  defp story_count(destination) do
    with {:ok, bytes} <- File.read(Path.join(destination, "index.json")),
         {:ok, %{"entries" => entries}} <- JSON.decode(bytes),
         true <- is_map(entries) and map_size(entries) > 0 do
      {:ok, map_size(entries)}
    else
      false -> {:error, :empty_storybook_index}
      {:error, reason} -> {:error, {:invalid_storybook_index, reason}}
      _ -> {:error, :invalid_storybook_index}
    end
  end

  defp source_revision(source) do
    case System.cmd("git", ["-C", source, "rev-parse", "HEAD"],
           env: CommandEnvironment.cleared(),
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        revision = String.trim(output)

        if Regex.match?(~r/\A[0-9a-f]{40}\z/, revision),
          do: {:ok, revision},
          else: {:error, {:invalid_storybook_source_revision, revision}}

      {output, status} ->
        {:error, {:storybook_source_revision_failed, status, tail(output)}}
    end
  end

  defp manifest(base_path, package, contract, stories, files, output_digest, revision) do
    %{
      "schema_version" => @schema,
      "base_path" => base_path,
      "entrypoint" => "index.html",
      "index" => "index.json",
      "source_revision" => revision,
      "wotex_lab" => %{
        "host_version" => WotexLabWorkbench.version(),
        "npm_package" => package["name"],
        "npm_version" => package["version"]
      },
      "storybook_version" => package["storybook_version"],
      "design_system" => contract,
      "story_count" => stories,
      "file_count" => files,
      "output_digest_algorithm" => "sha256-path-nul-content-v1",
      "output_digest" => output_digest
    }
  end

  defp write_manifest(destination, manifest) do
    case DocShell.Json.Canonical.encode(manifest) do
      {:ok, bytes} ->
        File.write(Path.join(destination, @manifest), bytes, [:binary, :exclusive, :sync])

      {:error, _} = error ->
        error
    end
  end

  defp read_manifest(root) do
    with {:ok, bytes} <- File.read(Path.join(root, @manifest)),
         true <- byte_size(bytes) <= 1_048_576,
         {:ok, manifest} <- JSON.decode(bytes),
         true <- is_map(manifest) do
      {:ok, manifest}
    else
      false -> {:error, :invalid_storybook_manifest}
      {:error, reason} -> {:error, {:invalid_storybook_manifest, reason}}
      _ -> {:error, :invalid_storybook_manifest}
    end
  end

  defp validate_manifest(manifest, base_path) do
    {:ok, contract} = DesignContract.current()

    with true <- manifest["schema_version"] == @schema,
         true <- manifest["base_path"] == base_path,
         true <- manifest["entrypoint"] == "index.html",
         true <- manifest["index"] == "index.json",
         true <- digest?(manifest["output_digest"]),
         true <- manifest["design_system"] == contract do
      :ok
    else
      false -> {:error, :invalid_storybook_manifest_contract}
    end
  end

  defp tree_digest(root, files) do
    result =
      Enum.reduce_while(files, {:ok, :crypto.hash_init(:sha256)}, fn relative, {:ok, state} ->
        case File.read(Path.join(root, relative)) do
          {:ok, bytes} ->
            {:cont, {:ok, :crypto.hash_update(state, [relative, <<0>>, bytes, <<0>>])}}

          {:error, reason} ->
            {:halt, {:error, {:storybook_digest_failed, relative, reason}}}
        end
      end)

    with {:ok, state} <- result do
      {:ok, "sha256:" <> Base.encode16(:crypto.hash_final(state), case: :lower)}
    end
  end

  defp digest?("sha256:" <> hex),
    do: byte_size(hex) == 64 and Regex.match?(~r/\A[0-9a-f]{64}\z/, hex)

  defp digest?(_), do: false
  defp tail(output), do: String.trim(String.slice(output, -8_192, 8_192))
end
