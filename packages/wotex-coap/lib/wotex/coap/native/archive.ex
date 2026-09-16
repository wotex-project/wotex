defmodule Wotex.CoAP.Native.Archive do
  @moduledoc """
  Verifies and extracts the bounded pinned libcoap source archive.

  `extract/3` reads one immutable archive snapshot, checks its SHA-256 and
  validates every tar entry before creating output. Only ordinary files and
  directories below the declared archive root are admitted. Links, duplicate
  paths, traversal, special files, privileged modes and excessive expansion
  fail without extraction. A failed unpack removes only the destination this
  call created.
  """

  import Bitwise, only: [band: 2]

  @archive_limit 4 * 1024 * 1024
  @expanded_limit 128 * 1024 * 1024
  @member_limit 32 * 1024 * 1024
  @entry_limit 20_000

  @typedoc "A finite archive verification or extraction failure."
  @type failure ::
          :invalid_archive_options
          | :archive_unreadable
          | :archive_limit
          | :source_digest_mismatch
          | :invalid_archive
          | :invalid_archive_entry
          | :archive_expansion_limit
          | :destination_exists
          | :destination_unavailable
          | :extraction_failed
          | :cleanup_failed

  @doc "Verifies and extracts one archive into a new absolute destination."
  @spec extract(term(), term(), term()) :: :ok | {:error, failure()}
  def extract(archive, destination, %{root: root, sha256: sha256})
      when is_binary(archive) and is_binary(destination) and is_binary(root) and
             is_binary(sha256) do
    with :ok <- options(archive, destination, root, sha256),
         {:ok, bytes} <- read(archive),
         :ok <- digest(bytes, sha256),
         {:ok, entries} <- table(bytes),
         :ok <- validate_entries(entries, root),
         :ok <- create_destination(destination) do
      unpack(bytes, destination)
    end
  end

  def extract(_, _, _), do: {:error, :invalid_archive_options}

  @doc "Checks tar metadata without writing files or trusting member paths."
  @spec validate_entries(term(), term()) :: :ok | {:error, failure()}
  def validate_entries(entries, root) when is_list(entries) and is_binary(root) do
    if valid_root?(root) and length(entries) in 1..@entry_limit do
      case Enum.reduce_while(entries, {0, MapSet.new()}, &entry(&1, &2, root)) do
        {:error, _} = error -> error
        {_, names} -> if MapSet.size(names) > 0, do: :ok, else: {:error, :invalid_archive_entry}
      end
    else
      {:error, :archive_expansion_limit}
    end
  rescue
    _ in [ArgumentError, UnicodeConversionError] -> {:error, :invalid_archive_entry}
  end

  def validate_entries(_, _), do: {:error, :invalid_archive_entry}

  defp options(archive, destination, root, sha256) do
    if Path.type(archive) == :absolute and Path.type(destination) == :absolute and
         valid_root?(root) and Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256) do
      :ok
    else
      {:error, :invalid_archive_options}
    end
  end

  defp valid_root?(root) do
    byte_size(root) in 1..128 and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/, root) and
      root not in [".", ".."]
  end

  defp read(path) do
    case File.open(path, [:read, :binary, :raw], &IO.binread(&1, @archive_limit + 1)) do
      {:ok, bytes} when is_binary(bytes) and byte_size(bytes) <= @archive_limit -> {:ok, bytes}
      {:ok, bytes} when is_binary(bytes) -> {:error, :archive_limit}
      _ -> {:error, :archive_unreadable}
    end
  end

  defp digest(bytes, expected) do
    if Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == expected,
      do: :ok,
      else: {:error, :source_digest_mismatch}
  end

  defp table(bytes) do
    case :erl_tar.table({:binary, bytes}, [:compressed, :verbose]) do
      {:ok, entries} -> {:ok, entries}
      {:error, _} -> {:error, :invalid_archive}
    end
  end

  # GitHub codeload archives contain this ignored POSIX global metadata header.
  defp entry({~c"pax_global_header", :unknown, size, _, _, _, _}, state, _)
       when size in 0..1024,
       do: {:cont, state}

  defp entry({name, kind, size, _, mode, _, _}, {total, names}, root)
       when is_list(name) and kind in [:regular, :directory] and is_integer(size) and
              is_integer(mode) and size >= 0 do
    path = String.trim_trailing(List.to_string(name), "/")

    cond do
      not valid_path?(path, root) or MapSet.member?(names, path) or band(mode, 0o7000) != 0 ->
        {:halt, {:error, :invalid_archive_entry}}

      exceeds_size?(kind, size, total) ->
        {:halt, {:error, :archive_expansion_limit}}

      true ->
        {:cont, {total + size, MapSet.put(names, path)}}
    end
  end

  defp entry(_, _, _), do: {:halt, {:error, :invalid_archive_entry}}

  defp exceeds_size?(kind, size, total) do
    size > @member_limit or total + size > @expanded_limit or (kind == :directory and size != 0)
  end

  defp valid_path?(path, root) do
    String.valid?(path) and byte_size(path) <= 4096 and
      (path == root or String.starts_with?(path, root <> "/")) and
      not String.contains?(path, ["\\", ":", <<0>>]) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."])) and
      length(String.split(path, "/")) <= 64
  end

  defp create_destination(destination) do
    case File.mkdir(destination) do
      :ok -> :ok
      {:error, :eexist} -> {:error, :destination_exists}
      {:error, _} -> {:error, :destination_unavailable}
    end
  end

  defp unpack(bytes, destination) do
    options = [:compressed, {:cwd, String.to_charlist(destination)}]

    case :erl_tar.extract({:binary, bytes}, options) do
      :ok ->
        :ok

      {:error, _} ->
        case File.rm_rf(destination) do
          {:ok, _} -> {:error, :extraction_failed}
          {:error, _, _} -> {:error, :cleanup_failed}
        end
    end
  end
end
