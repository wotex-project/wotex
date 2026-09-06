defmodule Wotex.Conformance.Artifact do
  @moduledoc """
  Streaming digest verification for an immutable subject archive.

  Symbolic links and non-regular files are rejected. Verification performs no
  extraction and starts no subject code. The byte budget is enforced while
  reading, and the returned size counts the bytes actually hashed. Consumers
  must keep the file unchanged through verification and subsequent execution;
  this check does not lock the path or provide filesystem isolation.
  """

  alias Wotex.Conformance.{Canonical, Error, Input}

  @default_max_bytes 1_073_741_824
  @chunk_bytes 65_536

  @type verification :: %{digest: String.t(), size_bytes: non_neg_integer()}

  @doc """
  Verifies that `path` is a bounded regular file with `expected_digest`.

  The digest must use the `sha256:` prefix and lowercase hexadecimal form.
  Use `:max_bytes` to replace the one-gibibyte default size limit. Reads stop
  after at most one byte beyond that budget, including when a file grows while
  being read. The reported size is independent of filesystem size metadata.
  """
  @spec verify(Path.t(), String.t(), keyword()) ::
          {:ok, verification()} | {:error, Error.t()}
  def verify(path, expected_digest, options \\ []) do
    with :ok <- Input.options(options, [:max_bytes]),
         max_bytes = Keyword.get(options, :max_bytes, @default_max_bytes),
         :ok <- validate_path(path),
         :ok <- validate_digest(expected_digest),
         :ok <- validate_max_bytes(max_bytes),
         {:ok, verification} <- digest_regular_file(path, max_bytes),
         :ok <- compare_digest(verification.digest, expected_digest) do
      {:ok, verification}
    end
  end

  @doc """
  Returns the lowercase SHA-256 digest of a bounded regular file.

  Hashing uses the default one-gibibyte streaming limit and rejects symbolic
  links and non-regular files. Use `verify/3` to select a different limit while
  checking an expected digest.
  """
  @spec digest_file(Path.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def digest_file(path) do
    with :ok <- validate_path(path),
         {:ok, verification} <- digest_regular_file(path, @default_max_bytes) do
      {:ok, verification.digest}
    end
  end

  defp digest_regular_file(path, max_bytes) do
    with :ok <- regular_file(path),
         {:ok, io} <- File.open(path, [:read, :binary]) do
      try do
        digest_stream(io, :crypto.hash_init(:sha256), 0, max_bytes)
      after
        File.close(io)
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, _reason} ->
        {:error, Error.new(:artifact_unreadable, "subject artifact could not be opened")}
    end
  end

  defp digest_stream(io, context, size_bytes, max_bytes) do
    read_bytes = min(@chunk_bytes, max_bytes - size_bytes + 1)

    case IO.binread(io, read_bytes) do
      :eof ->
        digest = "sha256:" <> Base.encode16(:crypto.hash_final(context), case: :lower)
        {:ok, %{digest: digest, size_bytes: size_bytes}}

      {:error, _reason} ->
        {:error, Error.new(:artifact_unreadable, "subject artifact could not be read")}

      bytes ->
        next_size = size_bytes + byte_size(bytes)

        with :ok <- within_limit(next_size, max_bytes) do
          digest_stream(io, :crypto.hash_update(context, bytes), next_size, max_bytes)
        end
    end
  end

  defp validate_path(path) when is_binary(path) and path != "", do: :ok

  defp validate_path(_path),
    do: {:error, Error.new(:invalid_artifact_path, "artifact path must be a non-empty string")}

  defp validate_digest(digest) do
    if Canonical.valid_digest?(digest) do
      :ok
    else
      {:error, Error.new(:invalid_digest, "artifact digest must be lowercase SHA-256")}
    end
  end

  defp validate_max_bytes(value) when is_integer(value) and value > 0, do: :ok

  defp validate_max_bytes(_value),
    do: {:error, Error.new(:invalid_limit, "artifact byte limit must be a positive integer")}

  defp regular_file(path) do
    case File.lstat(path, time: :posix) do
      {:ok, %File.Stat{type: :regular}} ->
        :ok

      {:ok, _stat} ->
        {:error, Error.new(:invalid_artifact_type, "subject artifact must be a regular file")}

      {:error, _reason} ->
        {:error, Error.new(:artifact_unreadable, "subject artifact could not be inspected")}
    end
  end

  defp within_limit(size, max_bytes) when size <= max_bytes, do: :ok

  defp within_limit(_size, max_bytes) do
    {:error,
     Error.new(:limit_exceeded, "subject artifact exceeds its byte limit",
       details: %{"max_bytes" => max_bytes}
     )}
  end

  defp compare_digest(actual, expected) do
    if secure_compare(actual, expected) do
      :ok
    else
      {:error,
       Error.new(:artifact_digest_mismatch, "subject artifact digest does not match",
         details: %{"actual_digest" => actual, "expected_digest" => expected}
       )}
    end
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {left_byte, right_byte}, acc ->
      Bitwise.bor(acc, Bitwise.bxor(left_byte, right_byte))
    end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false
end
