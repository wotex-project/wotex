defmodule Wotex.CoAP.Native.Workspace do
  @moduledoc """
  Owns one disposable native build workspace and its completion manifest.

  `run/4` builds only in an absent or empty absolute directory. A completed
  workspace is reused read-only after its build identity, exact file set and
  every artifact digest are verified again. Symlink ancestors, unrelated
  content, special files, malformed manifests and interrupted builds fail
  without repair or deletion.

  The builder runs in the caller and must create exactly the declared relative
  artifacts. On success this module adds content hashes and the build identity
  to `native-manifest.json`, then publishes the manifest with an atomic rename.
  Subprocess limits and the semantic native probes belong to the build owner.
  """

  @lock ".wotex-coap-build.lock"
  @manifest "native-manifest.json"
  @pending ".native-manifest.json.pending"
  @maximum_artifact 536_870_912
  @maximum_manifest 1_048_576

  @typedoc "A verified manifest and whether its existing artifacts were reused."
  @type result :: %{manifest: map(), reused: boolean()}

  @doc "Builds an empty owned workspace or verifies a completed one without mutation."
  @spec run(term(), term(), term(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, result()} | {:error, term()}
  def run(path, identity, artifacts, builder) when is_function(builder, 0) do
    with :ok <- validate(path, identity, artifacts),
         :ok <- safe_ancestors(path),
         {:ok, state} <- state(path) do
      case state do
        :empty -> build(path, identity, artifacts, builder)
        manifest -> reuse(path, identity, artifacts, manifest)
      end
    end
  end

  def run(_, _, _, _), do: {:error, :invalid_build_workspace}

  @doc "Returns the lowercase streaming SHA-256 of one bounded ordinary file."
  @spec digest(term()) :: {:ok, String.t()} | {:error, :invalid_build_artifact}
  def digest(path) when is_binary(path) do
    with {:ok, %{type: :regular, size: size}} when size <= @maximum_artifact <- File.lstat(path),
         {:ok, file} <- File.open(path, [:read, :binary, :raw]) do
      try do
        hash(file, :crypto.hash_init(:sha256), 0)
      after
        File.close(file)
      end
    else
      _ -> {:error, :invalid_build_artifact}
    end
  end

  def digest(_), do: {:error, :invalid_build_artifact}

  defp hash(file, context, size) do
    case IO.binread(file, 1_048_576) do
      :eof ->
        {:ok, Base.encode16(:crypto.hash_final(context), case: :lower)}

      bytes when is_binary(bytes) and byte_size(bytes) + size <= @maximum_artifact ->
        hash(file, :crypto.hash_update(context, bytes), size + byte_size(bytes))

      _ ->
        {:error, :invalid_build_artifact}
    end
  end

  defp validate(path, identity, artifacts) do
    if absolute?(path) and is_map(identity) and json?(identity, 262_144) and
         is_list(artifacts) and length(artifacts) in 1..128 and
         length(Enum.uniq(artifacts)) == length(artifacts) and
         Enum.all?(artifacts, &relative?/1) do
      :ok
    else
      {:error, :invalid_build_workspace}
    end
  end

  defp absolute?(path) when is_binary(path) do
    String.valid?(path) and byte_size(path) in 1..4096 and Path.type(path) == :absolute and
      not String.contains?(path, [<<0>>, "\n", "\r"]) and
      Enum.all?(Path.split(path), &(&1 not in [".", ".."]))
  end

  defp absolute?(_), do: false

  defp relative?(path) when is_binary(path) do
    String.valid?(path) and byte_size(path) in 1..4096 and Path.type(path) == :relative and
      not String.contains?(path, [<<0>>, "\\", "\n", "\r"]) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."])) and
      path not in [@manifest, @lock, @pending]
  end

  defp relative?(_), do: false

  defp json?(value, maximum) do
    case Jason.encode(value) do
      {:ok, bytes} -> byte_size(bytes) <= maximum
      _ -> false
    end
  rescue
    _ in [Protocol.UndefinedError, ArgumentError] -> false
  end

  defp safe_ancestors(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        :ok

      {:error, :enoent} ->
        parent = Path.dirname(path)

        if parent == path,
          do: {:error, :invalid_build_workspace},
          else: safe_ancestors(parent)

      _ ->
        {:error, :invalid_build_workspace}
    end
  end

  defp state(path) do
    case File.lstat(path) do
      {:error, :enoent} -> {:ok, :empty}
      {:ok, %{type: :directory}} -> directory_state(path)
      _ -> {:error, :invalid_build_workspace}
    end
  end

  defp directory_state(path) do
    case File.ls(path) do
      {:ok, []} ->
        {:ok, :empty}

      {:ok, names} ->
        if(@lock in names, do: {:error, :build_workspace_locked}, else: manifest(path))

      _ ->
        {:error, :invalid_build_workspace}
    end
  end

  defp manifest(path) do
    file = Path.join(path, @manifest)

    with {:ok, %{type: :regular, size: size}} when size <= @maximum_manifest <- File.lstat(file),
         {:ok, bytes} <- File.read(file),
         true <- byte_size(bytes) <= @maximum_manifest,
         {:ok, manifest} when is_map(manifest) <- Jason.decode(bytes) do
      {:ok, manifest}
    else
      _ -> {:error, :unrecognized_build_workspace}
    end
  end

  defp build(path, identity, artifacts, builder) do
    with :ok <- File.mkdir_p(path),
         :ok <- safe_ancestors(path),
         {:ok, lock} <- File.open(Path.join(path, @lock), [:write, :exclusive]) do
      try do
        with {:ok, [@lock]} <- File.ls(path),
             {:ok, manifest} when is_map(manifest) <- builder.(),
             {:ok, hashes} <- inventory(path, artifacts, [@lock]),
             {:ok, saved} <- save(path, identity, hashes, manifest) do
          {:ok, %{manifest: saved, reused: false}}
        else
          {:error, _} = error -> error
          _ -> {:error, :build_workspace_changed}
        end
      after
        File.close(lock)
        File.rm(Path.join(path, @lock))
      end
    else
      _ -> {:error, :build_workspace_locked}
    end
  rescue
    _ in File.Error -> {:error, :build_workspace_unavailable}
  end

  defp save(path, identity, hashes, manifest) do
    workspace = %{
      "format_version" => 1,
      "identity" => canonical(identity),
      "artifacts" => hashes
    }

    with true <- json?(manifest, @maximum_manifest),
         ready = Map.put(canonical(manifest), "workspace", workspace),
         true <- json?(ready, @maximum_manifest),
         {:ok, bytes} <- Jason.encode(ready),
         pending = Path.join(path, @pending),
         :ok <- File.write(pending, bytes <> "\n", [:exclusive, :sync]),
         :ok <- File.rename(pending, Path.join(path, @manifest)) do
      {:ok, ready}
    else
      _ ->
        File.rm(Path.join(path, @pending))
        {:error, :invalid_build_manifest}
    end
  end

  defp reuse(path, identity, artifacts, manifest) do
    with %{"format_version" => 1, "identity" => stored, "artifacts" => expected} <-
           manifest["workspace"],
         true <- stored == canonical(identity),
         {:ok, hashes} <- inventory(path, artifacts, [@manifest]),
         true <- hashes == expected do
      {:ok, %{manifest: manifest, reused: true}}
    else
      _ -> {:error, :build_manifest_mismatch}
    end
  end

  defp inventory(root, artifacts, ignored) do
    expected_files = MapSet.new(artifacts)
    expected_directories = artifact_directories(artifacts)

    with {:ok, files, directories} <- walk(root, root, ignored, [], []),
         true <- MapSet.new(files) == expected_files,
         true <- MapSet.new(directories) == expected_directories do
      digest_artifacts(root, artifacts)
    else
      _ -> {:error, :invalid_build_artifact}
    end
  end

  defp walk(root, directory, ignored, files, directories) do
    with {:ok, names} <- File.ls(directory) do
      Enum.reduce_while(names, {:ok, files, directories}, fn name, {:ok, found, dirs} ->
        walk_entry(root, directory, name, ignored, found, dirs)
      end)
    end
  end

  defp walk_entry(root, directory, name, ignored, found, directories) do
    path = Path.join(directory, name)
    relative = Path.relative_to(path, root)

    case File.lstat(path) do
      {:ok, %{type: :regular}} ->
        next = if relative in ignored, do: found, else: [relative | found]
        {:cont, {:ok, next, directories}}

      {:ok, %{type: :directory}} ->
        case walk(root, path, ignored, found, [relative | directories]) do
          {:ok, _, _} = next -> {:cont, next}
          error -> {:halt, error}
        end

      _ ->
        {:halt, {:error, :invalid_build_artifact}}
    end
  end

  defp artifact_directories(artifacts) do
    Enum.reduce(artifacts, MapSet.new(), fn artifact, result ->
      artifact
      |> Path.split()
      |> Enum.drop(-1)
      |> Enum.scan(fn part, parent -> Path.join(parent, part) end)
      |> Enum.reduce(result, &MapSet.put(&2, &1))
    end)
  end

  defp digest_artifacts(root, artifacts) do
    Enum.reduce_while(artifacts, {:ok, %{}}, fn relative, {:ok, hashes} ->
      case digest(Path.join(root, relative)) do
        {:ok, hash} -> {:cont, {:ok, Map.put(hashes, relative, hash)}}
        error -> {:halt, error}
      end
    end)
  end

  defp canonical(value), do: Jason.decode!(Jason.encode!(value))
end
