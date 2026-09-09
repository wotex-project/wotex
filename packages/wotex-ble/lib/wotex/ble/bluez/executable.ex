defmodule Wotex.BLE.BlueZ.Executable do
  @moduledoc """
  Admits one immutable deployment executable by its explicit SHA-256 identity.

  `verify/3` requires an absolute path, lowercase digest and BEAM monotonic
  deadline. It reads only an executable regular file of at most 64 MiB, hashes
  in 64 KiB chunks, and checks file identity before and after reading. Deadline
  equality is expired; hashing cannot restart the caller's budget. Errors contain
  no file content or filesystem exception text, and inspection omits the path.

  Missing, unreadable, oversized or non-executable files return
  `:transport_unavailable`; a digest or identity mismatch returns
  `:incompatible_backend`. Invalid selectors return `:invalid_options`.
  Error fields identify the executable without exposing its path or content.

  Verification performs filesystem I/O only when called. The consumer must keep
  admitted deployment files immutable: a later path-based spawn does not provide
  atomic execution of the hashed inode against adversarial file replacement.
  A bootstrap owner can run verification in a monitored worker so owner loss or
  its total deadline also interrupts a blocked filesystem operation.
  """

  alias Wotex.BLE.Error

  @maximum_file 67_108_864
  @maximum_clock 9_223_372_036_854_775_807
  @identity_fields [:inode, :major_device, :minor_device, :size, :mode, :mtime, :ctime]
  @enforce_keys [:path, :sha256, :bytes, :identity]
  @derive {Inspect, only: [:sha256, :bytes]}
  defstruct [:path, :sha256, :bytes, :identity]

  @type t :: %__MODULE__{
          path: String.t(),
          sha256: String.t(),
          bytes: pos_integer(),
          identity: map()
        }

  @doc "Verifies bounded regular-file content and stable metadata within an existing absolute deadline."
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
      _ -> incompatible()
    end
  end

  defp hash(file, context, size, deadline) do
    with :ok <- remaining(deadline) do
      case IO.binread(file, 65_536) do
        :eof ->
          {:ok, Base.encode16(:crypto.hash_final(context), case: :lower), size}

        bytes when is_binary(bytes) and byte_size(bytes) + size <= @maximum_file ->
          hash(file, :crypto.hash_update(context, bytes), size + byte_size(bytes), deadline)

        _ ->
          unavailable()
      end
    end
  end

  defp validate(path, digest, deadline) do
    if is_binary(path) and byte_size(path) in 1..4096 and String.valid?(path) and
         Path.type(path) == :absolute and not String.contains?(path, <<0>>) and
         is_binary(digest) and byte_size(digest) == 64 and
         Regex.match?(~r/\A[0-9a-f]{64}\z/, digest) and
         is_integer(deadline) and deadline >= -@maximum_clock - 1 and deadline <= @maximum_clock do
      :ok
    else
      invalid()
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
  defp invalid, do: {:error, Error.new(:invalid_options, :executable)}
end
