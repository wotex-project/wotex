defmodule Wotex.OPCUA.Native.Workspace do
  @moduledoc """
  Owns a disposable native build directory and its content-bound completion receipt.

  `run/4` accepts an absolute workspace, an explicit JSON-compatible build
  identity, relative artifact paths and a builder callback. A new workspace is
  locked with exclusive creation before the callback runs. A completed workspace
  is reusable only when its identity, artifact set and freshly computed file
  digests match. Reuse performs no write and never invokes the builder.

  A failed or interrupted build retains its owned files for diagnosis and cannot
  be mistaken for a complete build. Unrelated nonempty directories, symlink
  artifacts and malformed receipts fail without repair or deletion. The receipt
  describes build artifacts; it does not establish OPC UA service correctness.
  Callbacks run in the caller and remain responsible for bounded subprocesses.
  """

  @receipt "wotex-native-build.json"
  @lock ".wotex-opcua-build.lock"
  @maximum_file 536_870_912
  @maximum_receipt 1_048_576

  @typedoc "A content-bound JSON receipt and whether its verified artifacts were reused."
  @type result :: %{receipt: map(), reused: boolean()}

  @doc "Builds only an empty owned workspace, or verifies every artifact in a complete receipt."
  @spec run(term(), term(), term(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, result()} | {:error, term()}
  def run(path, identity, artifacts, builder) when is_function(builder, 0) do
    with :ok <- validate(path, identity, artifacts),
         {:ok, state} <- state(path) do
      case state do
        :empty -> build(path, identity, artifacts, builder)
        receipt -> reuse(path, identity, artifacts, receipt)
      end
    end
  end

  def run(_, _, _, _), do: {:error, :invalid_build_workspace}

  @doc "Computes a streaming SHA-256 for a regular artifact of at most 512 MiB."
  @spec digest(term()) :: {:ok, String.t()} | {:error, :invalid_build_artifact}
  def digest(path) when is_binary(path) do
    with {:ok, %{type: :regular, size: size}} when size <= @maximum_file <- File.lstat(path),
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

      bytes when is_binary(bytes) and byte_size(bytes) + size <= @maximum_file ->
        hash(file, :crypto.hash_update(context, bytes), size + byte_size(bytes))

      _ ->
        {:error, :invalid_build_artifact}
    end
  end

  defp validate(path, identity, artifacts) do
    if absolute?(path) and is_map(identity) and is_list(artifacts) and
         length(artifacts) in 1..64 and length(Enum.uniq(artifacts)) == length(artifacts) and
         Enum.all?(artifacts, &relative?/1) and json?(identity, 262_144) do
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
      path not in [@receipt, @lock]
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
        if @lock in names, do: {:error, :build_workspace_locked}, else: read_receipt(path)

      _ ->
        {:error, :invalid_build_workspace}
    end
  end

  defp read_receipt(path) do
    file = Path.join(path, @receipt)

    with {:ok, %{type: :regular, size: size}} when size <= @maximum_receipt <- File.lstat(file),
         {:ok, bytes} <- File.read(file),
         {:ok, receipt} when is_map(receipt) <- Jason.decode(bytes) do
      {:ok, receipt}
    else
      _ -> {:error, :unrecognized_build_workspace}
    end
  end

  defp build(path, identity, artifacts, builder) do
    with :ok <- File.mkdir_p(path),
         {:ok, lock} <- File.open(Path.join(path, @lock), [:write, :exclusive]) do
      try do
        with {:ok, [@lock]} <- File.ls(path),
             {:ok, evidence} when is_map(evidence) <- builder.(),
             {:ok, hashes} <- artifacts(path, artifacts) do
          save(path, identity, hashes, evidence)
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
  end

  defp save(path, identity, hashes, evidence) do
    receipt = %{
      "format_version" => 1,
      "identity" => Jason.decode!(Jason.encode!(identity)),
      "artifacts" => hashes,
      "evidence" => evidence
    }

    with true <- json?(receipt, @maximum_receipt),
         {:ok, bytes} <- Jason.encode(receipt),
         :ok <- File.write(Path.join(path, @receipt), bytes <> "\n", [:exclusive]) do
      {:ok, %{receipt: Jason.decode!(bytes), reused: false}}
    else
      _ -> {:error, :invalid_build_receipt}
    end
  end

  defp reuse(path, identity, paths, receipt) do
    with true <-
           MapSet.new(Map.keys(receipt)) ==
             MapSet.new(~w(format_version identity artifacts evidence)),
         true <- receipt["format_version"] == 1 and is_map(receipt["evidence"]),
         true <- receipt["identity"] == Jason.decode!(Jason.encode!(identity)),
         {:ok, hashes} <- artifacts(path, paths),
         true <- receipt["artifacts"] == hashes do
      {:ok, %{receipt: receipt, reused: true}}
    else
      _ -> {:error, :build_manifest_mismatch}
    end
  end

  defp artifacts(root, paths) do
    Enum.reduce_while(paths, {:ok, %{}}, fn relative, {:ok, result} ->
      with :ok <- no_links(root, relative),
           {:ok, digest} <- digest(Path.join(root, relative)) do
        {:cont, {:ok, Map.put(result, relative, digest)}}
      else
        _ -> {:halt, {:error, :invalid_build_artifact}}
      end
    end)
  end

  defp no_links(root, relative) do
    result =
      relative
      |> Path.split()
      |> Enum.reduce_while(root, fn part, parent ->
        path = Path.join(parent, part)

        case File.lstat(path) do
          {:ok, %{type: type}} when type in [:regular, :directory] -> {:cont, path}
          _ -> {:halt, {:error, :invalid_build_artifact}}
        end
      end)

    case result do
      {:error, _} = error -> error
      _ -> :ok
    end
  end
end
