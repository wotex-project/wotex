defmodule Wotex.Matter.Native.Executable do
  @moduledoc """
  Admits one immutable Matter controller host by explicit SHA-256 identity.

  Verification uses the caller's existing startup deadline. It accepts only a
  nonempty executable regular file, hashes through an open file descriptor and
  checks stable file identity before and after reading and against the final
  path. No controller process is started by this module.
  """

  alias Wotex.Matter.Error

  @maximum_file 536_870_912
  @maximum_clock 9_223_372_036_854_775_807
  @identity_fields [:inode, :major_device, :minor_device, :size, :mode, :mtime, :ctime]
  @enforce_keys [:path, :sha256, :bytes, :identity]
  @derive {Inspect, only: [:sha256, :bytes]}
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          path: String.t(),
          sha256: String.t(),
          bytes: pos_integer(),
          identity: map()
        }

  @doc "Verifies one executable within an existing absolute monotonic deadline."
  @spec verify(term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def verify(path, digest, deadline) do
    with :ok <- validate(path, digest, deadline),
         :ok <- remaining(deadline),
         {:ok, stat} <- File.lstat(path, time: :posix),
         true <- executable?(stat),
         {:ok, file} <- File.open(path, [:read, :binary, :raw]) do
      try do
        opened(file, path, digest, deadline, identity(stat))
      after
        File.close(file)
      end
    else
      {:error, %Error{}} = error -> error
      _ -> unavailable()
    end
  end

  defp opened(file, path, expected, deadline, identity) do
    with {:ok, record} <- :file.read_file_info(file, time: :posix),
         ^identity <- identity(File.Stat.from_record(record)),
         {:ok, digest, size} <- hash(file, :crypto.hash_init(:sha256), 0, deadline),
         true <- digest == expected,
         {:ok, record} <- :file.read_file_info(file, time: :posix),
         ^identity <- identity(File.Stat.from_record(record)),
         {:ok, stat} <- File.lstat(path, time: :posix),
         true <- executable?(stat),
         ^identity <- identity(stat),
         :ok <- remaining(deadline) do
      {:ok, %__MODULE__{path: path, sha256: digest, bytes: size, identity: identity}}
    else
      {:error, %Error{}} = error -> error
      {:error, :file_too_large} -> unavailable()
      _ -> incompatible()
    end
  end

  defp hash(file, context, size, deadline) do
    with :ok <- remaining(deadline) do
      case IO.binread(file, 65_536) do
        :eof ->
          digest = :crypto.hash_final(context) |> Base.encode16(case: :lower)
          {:ok, digest, size}

        bytes when is_binary(bytes) and byte_size(bytes) + size <= @maximum_file ->
          hash(file, :crypto.hash_update(context, bytes), size + byte_size(bytes), deadline)

        _ ->
          {:error, :file_too_large}
      end
    end
  end

  defp validate(path, digest, deadline) do
    if is_binary(path) and byte_size(path) in 1..4096 and String.valid?(path) and
         Path.type(path) == :absolute and not String.contains?(path, <<0>>) and
         is_binary(digest) and Regex.match?(~r/\A[0-9a-f]{64}\z/, digest) and
         is_integer(deadline) and deadline >= -@maximum_clock - 1 and deadline <= @maximum_clock do
      :ok
    else
      {:error, Error.new(:invalid_options, :executable)}
    end
  end

  defp executable?(%File.Stat{type: :regular, size: size, mode: mode}),
    do: size in 1..@maximum_file and Bitwise.band(mode, 0o111) != 0

  defp executable?(_), do: false
  defp identity(stat), do: Map.take(stat, @identity_fields)

  defp remaining(deadline) do
    if System.monotonic_time(:millisecond) < deadline,
      do: :ok,
      else: {:error, Error.new(:timeout, :executable)}
  end

  defp unavailable, do: {:error, Error.new(:transport_unavailable, :executable)}
  defp incompatible, do: {:error, Error.new(:incompatible_backend, :executable)}
end
