defmodule Wotex.Thread.Native.Workspace do
  @moduledoc """
  Owns an explicit disposable directory for a native or software fixture build.

  A build may start only in an empty, absolute, non-symlink directory. An
  existing nonempty directory is read-only until its completed manifest,
  identity and regular-file artifact hashes have all been verified. An
  interrupted build cannot be reused or silently repaired. Native builds write
  `native-manifest.json` with schema `wotex.native-build`; software fixture
  builds write `software-manifest.json` with schema `wotex.software-build`.
  """

  alias Wotex.Thread.Native.Source

  @manifests %{
    native: {"native-manifest.json", "wotex.native-build"},
    software: {"software-manifest.json", "wotex.software-build"}
  }
  @manifest_names ["native-manifest.json", "software-manifest.json"]
  @lock ".wotex-thread-build.lock"
  @maximum_manifest 1_048_576
  @identity_fields ~w(source_revision source_files upstream_sources json_header
    build_modules build_features arguments environment_allowlist)

  @typedoc "A verified build manifest and whether the builder was invoked."
  @type result :: %{manifest: map(), reused: boolean()}

  @typedoc "The manifest family owned by a workspace."
  @type kind :: :native | :software

  @doc "Validates the exact native build task argument shape."
  @spec arguments(term()) :: {:ok, Path.t(), boolean()} | {:error, atom()}
  def arguments(["--workspace", workspace]), do: validate_arguments(workspace, false)

  def arguments(["--sanitizers", "--workspace", workspace]),
    do: validate_arguments(workspace, true)

  def arguments(["--workspace", workspace, "--sanitizers"]),
    do: validate_arguments(workspace, true)

  def arguments(_), do: {:error, :invalid_native_build_arguments}

  @doc "Builds an empty workspace or verifies a completed manifest without mutation."
  @spec run(term(), term(), term(), (-> {:ok, map()} | {:error, term()}), kind()) ::
          {:ok, result()} | {:error, term()}
  def run(path, identity, artifacts, builder, kind \\ :native)

  def run(path, identity, artifacts, builder, kind)
      when is_function(builder, 0) and is_map_key(@manifests, kind) do
    with :ok <- validate(path, identity, artifacts),
         {:ok, state} <- state(path, kind) do
      case state do
        :empty -> build(path, identity, artifacts, builder, kind)
        manifest -> reuse(path, identity, artifacts, manifest, kind)
      end
    end
  end

  def run(_, _, _, _, _), do: {:error, :invalid_build_workspace}

  defp validate_arguments(workspace, sanitizers) do
    if absolute?(workspace),
      do: {:ok, workspace, sanitizers},
      else: {:error, :invalid_native_build_arguments}
  end

  defp validate(path, identity, artifacts) do
    if absolute?(path) and is_map(identity) and is_list(artifacts) and
         length(artifacts) in 1..64 and length(Enum.uniq(artifacts)) == length(artifacts) and
         Enum.all?(artifacts, &relative?/1) and json?(identity) and no_link_ancestors?(path) do
      :ok
    else
      {:error, :invalid_build_workspace}
    end
  end

  defp absolute?(path) when is_binary(path) do
    byte_size(path) in 2..4096 and String.valid?(path) and Path.type(path) == :absolute and
      path != "/" and not String.contains?(path, [<<0>>, "\n", "\r"]) and
      Enum.all?(Path.split(path), &(&1 not in [".", ".."]))
  end

  defp absolute?(_), do: false

  defp relative?(path) when is_binary(path) do
    byte_size(path) in 1..4096 and String.valid?(path) and Path.type(path) == :relative and
      not String.contains?(path, [<<0>>, "\\", "\n", "\r"]) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."])) and
      path not in [@lock | @manifest_names]
  end

  defp relative?(_), do: false

  defp no_link_ancestors?(path) do
    path
    |> Path.split()
    |> Enum.reduce_while("/", fn part, parent ->
      current = Path.join(parent, part)

      case File.lstat(current) do
        {:ok, %File.Stat{type: :directory}} -> {:cont, current}
        {:error, :enoent} -> {:cont, current}
        _ -> {:halt, false}
      end
    end)
    |> Kernel.!=(false)
  end

  defp json?(value) do
    case Jason.encode(value) do
      {:ok, bytes} -> byte_size(bytes) <= @maximum_manifest
      _ -> false
    end
  rescue
    _ -> false
  end

  defp state(path, kind) do
    case File.lstat(path) do
      {:error, :enoent} -> {:ok, :empty}
      {:ok, %File.Stat{type: :directory}} -> directory_state(path, kind)
      _ -> {:error, :invalid_build_workspace}
    end
  end

  defp directory_state(path, kind) do
    case File.ls(path) do
      {:ok, []} ->
        {:ok, :empty}

      {:ok, names} ->
        if @lock in names, do: {:error, :build_workspace_locked}, else: read(path, kind)

      _ ->
        {:error, :invalid_build_workspace}
    end
  end

  defp read(path, kind) do
    file = Path.join(path, manifest_name(kind))

    with {:ok, %File.Stat{type: :regular, size: size}} when size <= @maximum_manifest <-
           File.lstat(file),
         {:ok, bytes} <- File.read(file),
         {:ok, manifest} when is_map(manifest) <- Jason.decode(bytes) do
      {:ok, manifest}
    else
      _ -> {:error, :unrecognized_build_workspace}
    end
  end

  defp build(path, identity, artifacts, builder, kind) do
    with :ok <- File.mkdir_p(path),
         {:ok, lock} <- File.open(Path.join(path, @lock), [:write, :exclusive]) do
      result =
        try do
          with {:ok, [@lock]} <- File.ls(path),
               {:ok, evidence} when is_map(evidence) <- builder.(),
               {:ok, hashes} <- artifact_hashes(path, artifacts) do
            save(path, identity, hashes, evidence, kind)
          else
            {:error, _} = error -> error
            _ -> {:error, :build_workspace_changed}
          end
        after
          File.close(lock)
        end

      case result do
        {:ok, _} ->
          case File.rm(Path.join(path, @lock)) do
            :ok -> result
            _ -> {:error, :build_workspace_locked}
          end

        _ ->
          result
      end
    else
      _ -> {:error, :build_workspace_locked}
    end
  end

  defp save(path, identity, hashes, evidence, kind) do
    if json?(evidence) do
      manifest =
        %{
          "schema" => schema(kind),
          "version" => 1,
          "package" => "wotex_thread",
          "identity" => Jason.decode!(Jason.encode!(identity)),
          "artifacts" => hashes,
          "audit" => Jason.decode!(Jason.encode!(evidence)),
          "binaries" => binaries(evidence),
          "toolchain" => toolchain(identity, evidence)
        }
        |> Map.merge(Map.take(identity, @identity_fields))

      write_manifest(path, manifest, kind)
    else
      {:error, :invalid_build_manifest}
    end
  end

  defp write_manifest(path, manifest, kind) do
    with true <- json?(manifest),
         {:ok, bytes} <- Jason.encode(manifest),
         :ok <- File.write(Path.join(path, manifest_name(kind)), bytes <> "\n", [:exclusive]) do
      {:ok, %{manifest: manifest, reused: false}}
    else
      _ -> {:error, :invalid_build_manifest}
    end
  end

  defp reuse(path, identity, artifacts, manifest, kind) do
    expected_keys =
      MapSet.union(
        MapSet.new(~w(schema version package identity artifacts audit binaries toolchain)),
        MapSet.new(Map.keys(Map.take(identity, @identity_fields)))
      )

    with true <-
           MapSet.new(Map.keys(manifest)) == expected_keys,
         true <- manifest["schema"] == schema(kind) and manifest["version"] == 1,
         true <- manifest["package"] == "wotex_thread" and is_map(manifest["audit"]),
         true <- manifest["identity"] == Jason.decode!(Jason.encode!(identity)),
         true <- Map.take(manifest, @identity_fields) == Map.take(identity, @identity_fields),
         true <- manifest["binaries"] == binaries(manifest["audit"]),
         true <- manifest["toolchain"] == toolchain(identity, manifest["audit"]),
         {:ok, hashes} <- artifact_hashes(path, artifacts),
         true <- manifest["artifacts"] == hashes do
      {:ok, %{manifest: manifest, reused: true}}
    else
      _ -> {:error, :build_manifest_mismatch}
    end
  end

  defp manifest_name(kind), do: elem(Map.fetch!(@manifests, kind), 0)
  defp schema(kind), do: elem(Map.fetch!(@manifests, kind), 1)

  defp binaries(%{"binaries" => binaries}) when is_list(binaries), do: binaries
  defp binaries(%{"binary" => binary}) when is_map(binary), do: [binary]
  defp binaries(_), do: []

  defp toolchain(identity, evidence) do
    %{
      "executables" => Jason.decode!(Jason.encode!(identity["toolchain"])),
      "versions" => evidence["toolchain_versions"],
      "target_triple" => evidence["target_triple"]
    }
  end

  defp artifact_hashes(root, paths) do
    Enum.reduce_while(paths, {:ok, %{}}, fn relative, {:ok, result} ->
      with :ok <- no_links(root, relative),
           {:ok, digest} <- artifact_digest(Path.join(root, relative)) do
        {:cont, {:ok, Map.put(result, relative, digest)}}
      else
        _ -> {:halt, {:error, :invalid_build_artifact}}
      end
    end)
  end

  defp artifact_digest(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> Source.tree_digest(path)
      {:ok, %File.Stat{type: :regular}} -> Source.digest(path)
      _ -> {:error, :invalid_build_artifact}
    end
  end

  defp no_links(root, relative) do
    result =
      relative
      |> Path.split()
      |> Enum.reduce_while(root, fn part, parent ->
        current = Path.join(parent, part)

        case File.lstat(current) do
          {:ok, %File.Stat{type: type}} when type in [:directory, :regular] ->
            {:cont, current}

          _ ->
            {:halt, {:error, :invalid_build_artifact}}
        end
      end)

    case result do
      {:error, _} = error -> error
      _ -> :ok
    end
  end
end
