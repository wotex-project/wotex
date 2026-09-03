defmodule Wotex.Conformance.Artifact do
  @moduledoc """
  Streaming digest verification for an immutable subject archive.

  Symbolic links and non-regular files are rejected. Verification performs no
  extraction and starts no subject code.
  """

  alias Wotex.Conformance.{Canonical, Error}

  @default_max_bytes 1_073_741_824
  @chunk_bytes 65_536

  @type verification :: %{digest: String.t(), size_bytes: non_neg_integer()}

  @doc """
  Verifies that `path` is a bounded regular file with `expected_digest`.

  The digest must use the `sha256:` prefix and lowercase hexadecimal form.
  Use `:max_bytes` to replace the one-gibibyte default size limit.
  """
  @spec verify(Path.t(), String.t(), keyword()) ::
          {:ok, verification()} | {:error, Error.t()}
  def verify(path, expected_digest, options \\ []) do
    max_bytes = Keyword.get(options, :max_bytes, @default_max_bytes)

    with :ok <- validate_path(path),
         :ok <- validate_digest(expected_digest),
         :ok <- validate_max_bytes(max_bytes),
         {:ok, stat} <- regular_file_stat(path),
         :ok <- within_limit(stat.size, max_bytes),
         {:ok, actual_digest} <- digest_file(path),
         :ok <- compare_digest(actual_digest, expected_digest) do
      {:ok, %{digest: actual_digest, size_bytes: stat.size}}
    end
  end

  @doc "Returns the lowercase SHA-256 digest of a regular file without loading it into memory."
  @spec digest_file(Path.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def digest_file(path) do
    with :ok <- validate_path(path),
         {:ok, io} <- File.open(path, [:read, :binary]) do
      try do
        case digest_stream(io, :crypto.hash_init(:sha256)) do
          {:ok, digest} -> {:ok, "sha256:" <> Base.encode16(digest, case: :lower)}
          {:error, error} -> {:error, error}
        end
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

  defp digest_stream(io, context) do
    case IO.binread(io, @chunk_bytes) do
      :eof ->
        {:ok, :crypto.hash_final(context)}

      {:error, _reason} ->
        {:error, Error.new(:artifact_unreadable, "subject artifact could not be read")}

      bytes ->
        digest_stream(io, :crypto.hash_update(context, bytes))
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

  defp regular_file_stat(path) do
    case File.lstat(path, time: :posix) do
      {:ok, %File.Stat{type: :regular} = stat} ->
        {:ok, stat}

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
