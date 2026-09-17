defmodule Wotex.BLE.Native.Workspace do
  @moduledoc """
  Owns one explicit disposable native build directory and its manifest.

  A build starts only in an absent or empty absolute directory without symbolic
  link ancestors. An exclusive lock file marks the owned build while the builder
  callback runs. A nonempty directory is read-only: it is reusable only when its
  `native-manifest.json` has the exact schema, identity and freshly recomputed
  artifact digests. Unrelated, interrupted and locked directories fail without
  deletion or repair.

  The manifest has schema `wotex.native-build`, version 1 and package
  `wotex_ble`. It records source, upstream, toolchain, argument, feature, binary
  and audit evidence supplied by the builder. It is not successful execution
  evidence for BlueZ, D-Bus or GATT behavior.
  """

  alias Wotex.BLE.Native.Source

  @manifest "native-manifest.json"
  @lock ".wotex-ble-build.lock"
  @maximum_manifest 1_048_576
  @identity_fields ~w(source_revision source_files build_sources upstream_sources arguments
    environment_allowlist build_features)
  @manifest_fields ~w(schema version package identity artifacts toolchain binaries audit)

  @typedoc "A verified manifest and whether the build callback was invoked."
  @type result :: %{manifest: map(), reused: boolean()}

  @doc "Validates the exact task argument vector before any build I/O."
  @spec arguments(term()) :: {:ok, String.t()} | {:error, :invalid_native_build_arguments}
  def arguments(["--workspace", workspace]) do
    if absolute?(workspace), do: {:ok, workspace}, else: {:error, :invalid_native_build_arguments}
  end

  def arguments(_), do: {:error, :invalid_native_build_arguments}

  @doc "Builds an empty owned workspace, or verifies a completed one without mutation."
  @spec run(term(), term(), term(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, result()} | {:error, term()}
  def run(path, identity, artifacts, builder) when is_function(builder, 0) do
    with :ok <- validate(path, identity, artifacts),
         {:ok, state} <- state(path) do
      case state do
        :empty -> build(path, identity, artifacts, builder)
        manifest -> reuse(path, identity, artifacts, manifest)
      end
    end
  end

  def run(_, _, _, _), do: {:error, :invalid_build_workspace}

  defp validate(path, identity, artifacts) do
    if absolute?(path) and is_map(identity) and
         Enum.all?(["toolchain" | @identity_fields], &Map.has_key?(identity, &1)) and
         is_list(artifacts) and
         length(artifacts) in 1..64 and length(Enum.uniq(artifacts)) == length(artifacts) and
         Enum.all?(artifacts, &relative?/1) and json?(identity) and no_link_ancestors?(path) do
      :ok
    else
      {:error, :invalid_build_workspace}
    end
  end

  defp absolute?(path) do
    is_binary(path) and byte_size(path) in 2..4096 and String.valid?(path) and
      Path.type(path) == :absolute and not String.contains?(path, [<<0>>, "\n", "\r"]) and
      Enum.all?(Path.split(path), &(&1 not in [".", ".."]))
  end

  defp relative?(path) do
    is_binary(path) and byte_size(path) in 1..4096 and String.valid?(path) and
      Path.type(path) == :relative and not String.contains?(path, [<<0>>, "\\", "\n", "\r"]) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."])) and
      path not in [@manifest, @lock]
  end

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
    |> is_binary()
  end

  defp json?(value) do
    case Jason.encode(value) do
      {:ok, bytes} -> byte_size(bytes) <= @maximum_manifest
      _ -> false
    end
  end

  # Validation already admitted only an absent path or a directory ancestor chain.
  defp state(path) do
    if File.exists?(path), do: directory_state(path), else: {:ok, :empty}
  end

  defp directory_state(path) do
    case File.ls(path) do
      {:ok, []} -> {:ok, :empty}
      {:ok, names} -> if @lock in names, do: {:error, :build_workspace_locked}, else: read(path)
      _ -> {:error, :invalid_build_workspace}
    end
  end

  defp read(path) do
    file = Path.join(path, @manifest)

    with {:ok, %File.Stat{type: :regular, size: size}} when size <= @maximum_manifest <-
           File.lstat(file),
         {:ok, bytes} <- File.read(file),
         {:ok, manifest} when is_map(manifest) <- Jason.decode(bytes) do
      {:ok, manifest}
    else
      _ -> {:error, :unrecognized_build_workspace}
    end
  end

  defp build(path, identity, artifacts, builder) do
    with :ok <- File.mkdir_p(path),
         {:ok, lock} <- File.open(Path.join(path, @lock), [:write, :exclusive]) do
      result =
        try do
          with {:ok, [@lock]} <- File.ls(path),
               {:ok, evidence} when is_map(evidence) <- builder.(),
               {:ok, hashes} <- artifact_hashes(path, artifacts) do
            save(path, identity, hashes, evidence)
          else
            {:error, _} = error -> error
            _ -> {:error, :build_workspace_changed}
          end
        after
          File.close(lock)
        end

      release(path, result)
    else
      _ -> {:error, :build_workspace_locked}
    end
  end

  # A failed build keeps its lock so the directory cannot be mistaken for reuse.
  defp release(path, {:ok, _} = result) do
    case File.rm(Path.join(path, @lock)) do
      :ok -> result
      _ -> {:error, :build_workspace_locked}
    end
  end

  defp release(_, result), do: result

  defp save(path, identity, hashes, evidence) do
    manifest =
      identity
      |> Map.take(@identity_fields)
      |> Map.merge(%{
        "schema" => "wotex.native-build",
        "version" => 1,
        "package" => "wotex_ble",
        "identity" => normalize(identity),
        "artifacts" => hashes,
        "toolchain" => toolchain(identity, evidence),
        "binaries" => Map.get(evidence, "binaries"),
        "audit" => normalize(evidence)
      })
      |> normalize()

    with true <- json?(manifest),
         {:ok, bytes} <- Jason.encode(manifest),
         :ok <- File.write(Path.join(path, @manifest), bytes <> "\n", [:exclusive]) do
      {:ok, %{manifest: manifest, reused: false}}
    else
      _ -> {:error, :invalid_build_manifest}
    end
  end

  defp reuse(path, identity, artifacts, manifest) do
    expected = MapSet.new(@manifest_fields ++ @identity_fields)

    with true <- MapSet.new(Map.keys(manifest)) == expected,
         true <- manifest["schema"] == "wotex.native-build" and manifest["version"] == 1,
         true <- manifest["package"] == "wotex_ble" and is_map(manifest["audit"]),
         true <- manifest["identity"] == normalize(identity),
         true <-
           Map.take(manifest, @identity_fields) == normalize(Map.take(identity, @identity_fields)),
         true <- manifest["toolchain"] == normalize(toolchain(identity, manifest["audit"])),
         true <- manifest["binaries"] == manifest["audit"]["binaries"],
         {:ok, hashes} <- artifact_hashes(path, artifacts),
         true <- manifest["artifacts"] == hashes do
      {:ok, %{manifest: manifest, reused: true}}
    else
      _ -> {:error, :build_manifest_mismatch}
    end
  end

  defp toolchain(identity, evidence) do
    %{
      "executables" => Map.get(identity, "toolchain"),
      "versions" => Map.get(evidence, "toolchain_versions"),
      "target_triple" => Map.get(evidence, "target_triple")
    }
  end

  defp normalize(value) do
    encoded = Jason.encode!(value)
    Jason.decode!(encoded)
  end

  defp artifact_hashes(root, paths) do
    Enum.reduce_while(paths, {:ok, %{}}, fn relative, {:ok, result} ->
      with {:ok, type} <- no_links(root, relative),
           {:ok, digest} <- artifact_digest(Path.join(root, relative), type) do
        {:cont, {:ok, Map.put(result, relative, digest)}}
      else
        _ -> {:halt, {:error, :invalid_build_artifact}}
      end
    end)
  end

  defp artifact_digest(path, :directory), do: Source.tree_digest(path)
  defp artifact_digest(path, :regular), do: Source.digest(path)

  defp no_links(root, relative) do
    result =
      relative
      |> Path.split()
      |> Enum.reduce_while(root, fn part, parent ->
        current = Path.join(parent, part)

        case File.lstat(current) do
          {:ok, %File.Stat{type: type}} when type in [:directory, :regular] -> {:cont, current}
          _ -> {:halt, :error}
        end
      end)

    if result == :error,
      do: {:error, :invalid_build_artifact},
      else: {:ok, File.lstat!(result).type}
  end
end
