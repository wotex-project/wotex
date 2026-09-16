defmodule Wotex.Thread.Native.Source do
  @moduledoc """
  Validates pinned native source archives and applies exact SDK fixes.

  This explicit build helper performs no work during dependency loading. It
  accepts only regular files and directories under the named archive root,
  verifies both sides of each reviewed source change before writing, and
  requires an explicit absolute extraction destination.
  """

  @archive_files 100_000
  @archive_bytes 512 * 1024 * 1024
  @download_bytes 128 * 1024 * 1024
  @download_ms 120_000

  @doc "Fetches one HTTPS source archive within the byte limit, or verifies its cached SHA-256."
  @spec fetch(String.t(), Path.t(), String.t()) :: :ok | {:error, atom()}
  def fetch(url, target, expected)
      when is_binary(url) and is_binary(target) and is_binary(expected) do
    with true <-
           pinned_url?(url) and Path.type(target) == :absolute and
             String.match?(expected, ~r/\A[0-9a-f]{64}\z/),
         :ok <- cached_or_absent(target, expected) do
      if File.exists?(target), do: :ok, else: download(url, target, expected)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_source_download}
    end
  end

  def fetch(_, _, _), do: {:error, :invalid_source_download}

  @doc "Returns the lowercase SHA-256 digest of one regular file."
  @spec digest(Path.t()) :: {:ok, String.t()} | {:error, atom()}
  def digest(path) when is_binary(path) do
    with {:ok, %File.Stat{type: :regular}} <- File.lstat(path),
         {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        hash = hash_file(file, :crypto.hash_init(:sha256))
        {:ok, Base.encode16(:crypto.hash_final(hash), case: :lower)}
      after
        File.close(file)
      end
    else
      _ -> {:error, :invalid_source_file}
    end
  end

  def digest(_), do: {:error, :invalid_source_file}

  @doc "Hashes a regular-file tree in deterministic relative-path order and rejects links."
  @spec tree_digest(Path.t()) :: {:ok, String.t()} | {:error, atom()}
  def tree_digest(path) when is_binary(path) do
    with {:ok, %File.Stat{type: :directory}} <- File.lstat(path),
         {:ok, files} <- tree_files(path, ""),
         {:ok, hash} <- hash_tree(path, Enum.sort(files), :crypto.hash_init(:sha256)) do
      {:ok, Base.encode16(:crypto.hash_final(hash), case: :lower)}
    else
      _ -> {:error, :invalid_source_tree}
    end
  end

  def tree_digest(_), do: {:error, :invalid_source_tree}

  @doc "Returns the reviewed relative file names and SHA-256 digests of a source tree."
  @spec file_hashes(Path.t()) :: {:ok, map()} | {:error, atom()}
  def file_hashes(path) when is_binary(path) do
    with {:ok, %File.Stat{type: :directory}} <- File.lstat(path),
         {:ok, files} <- tree_files(path, "") do
      Enum.reduce_while(files, {:ok, %{}}, fn relative, {:ok, hashes} ->
        case digest(Path.join(path, relative)) do
          {:ok, hash} -> {:cont, {:ok, Map.put(hashes, relative, hash)}}
          _ -> {:halt, {:error, :invalid_source_tree}}
        end
      end)
    else
      _ -> {:error, :invalid_source_tree}
    end
  end

  def file_hashes(_), do: {:error, :invalid_source_tree}

  @doc "Copies only regular files and directories into an owned SDK source tree."
  @spec copy_tree(Path.t(), Path.t()) :: :ok | {:error, atom()}
  def copy_tree(source, destination) when is_binary(source) and is_binary(destination) do
    with {:ok, %File.Stat{type: :directory}} <- File.lstat(source),
         :ok <- ensure_directory(destination),
         {:ok, names} <- File.ls(source) do
      Enum.reduce_while(names, :ok, fn name, :ok ->
        case copy_entry(Path.join(source, name), Path.join(destination, name)) do
          :ok -> {:cont, :ok}
          _ -> {:halt, {:error, :invalid_source_tree}}
        end
      end)
    else
      _ -> {:error, :invalid_source_tree}
    end
  end

  def copy_tree(_, _), do: {:error, :invalid_source_tree}

  @doc "Checks a gzip tar archive's finite regular-file tree before extraction."
  @spec validate_archive(Path.t(), String.t()) :: {:ok, list()} | {:error, atom()}
  def validate_archive(path, root) when is_binary(path) and is_binary(root) do
    case :erl_tar.table(String.to_charlist(path), [:compressed, :verbose]) do
      {:ok, entries} when length(entries) <= @archive_files ->
        validate_entries(skip_global_header(entries), root, 0)

      _ ->
        {:error, :invalid_source_archive}
    end
  rescue
    _ -> {:error, :invalid_source_archive}
  end

  def validate_archive(_, _), do: {:error, :invalid_source_archive}

  @doc "Extracts a previously validated archive into an empty owned directory."
  @spec extract(Path.t(), Path.t(), String.t()) :: :ok | {:error, atom()}
  def extract(archive, destination, root) do
    with true <- Path.type(destination) == :absolute,
         {:ok, entries} <- validate_archive(archive, root),
         :ok <- empty_directory(destination),
         :ok <-
           :erl_tar.extract(String.to_charlist(archive), [
             :compressed,
             {:cwd, String.to_charlist(destination)}
           ]) do
      Enum.each(entries, &normalize_permissions(destination, &1))
      :ok
    else
      _ -> {:error, :invalid_source_archive}
    end
  rescue
    _ -> {:error, :invalid_source_archive}
  end

  @doc "Applies the pinned unsigned Spinel shifts after exact before/after hash checks."
  @spec patch_spinel(Path.t(), map()) :: :ok | {:error, atom()}
  def patch_spinel(sdk, pin) do
    replacements = [
      {"(data_in[3] << 24)", "((uint32_t)data_in[3] << 24)", 2},
      {"(data_in[7] << 24)", "((uint32_t)data_in[7] << 24)", 1}
    ]

    patch(sdk, pin, "src/lib/spinel/spinel.c", replacements)
  end

  @doc "Applies the pinned full-width discerner mask after exact hash checks."
  @spec patch_discerner(Path.t(), map()) :: :ok | {:error, atom()}
  def patch_discerner(sdk, pin) do
    patch(sdk, pin, "src/core/meshcop/meshcop.hpp", [
      {"return (static_cast<uint64_t>(1ULL) << mLength) - 1;",
       "return mLength == 64 ? ~static_cast<uint64_t>(0) : (static_cast<uint64_t>(1ULL) << mLength) - 1;",
       1}
    ])
  end

  defp hash_file(file, hash) do
    case IO.binread(file, 1_048_576) do
      :eof -> hash
      bytes -> hash_file(file, :crypto.hash_update(hash, bytes))
    end
  end

  defp tree_files(root, relative) do
    case File.ls(Path.join(root, relative)) do
      {:ok, names} ->
        Enum.reduce_while(names, {:ok, []}, fn name, {:ok, files} ->
          path = Path.join(relative, name)

          case tree_entry(root, path) do
            {:ok, children} -> {:cont, {:ok, children ++ files}}
            error -> {:halt, error}
          end
        end)

      _ ->
        {:error, :invalid_source_tree}
    end
  end

  defp tree_entry(root, relative) do
    case File.lstat(Path.join(root, relative)) do
      {:ok, %File.Stat{type: :directory}} -> tree_files(root, relative)
      {:ok, %File.Stat{type: :regular}} -> {:ok, [relative]}
      _ -> {:error, :invalid_source_tree}
    end
  end

  defp hash_tree(_, [], hash), do: {:ok, hash}

  defp hash_tree(root, [relative | rest], hash) do
    case digest(Path.join(root, relative)) do
      {:ok, file_hash} ->
        next = :crypto.hash_update(hash, ["file", <<0>>, relative, <<0>>, file_hash, <<0>>])
        hash_tree(root, rest, next)

      _ ->
        {:error, :invalid_source_tree}
    end
  end

  defp copy_entry(source, destination) do
    case File.lstat(source) do
      {:ok, %File.Stat{type: :directory}} ->
        copy_tree(source, destination)

      {:ok, %File.Stat{type: :regular, mode: mode}} ->
        with :ok <- regular_or_absent(destination),
             :ok <- File.cp(source, destination) do
          File.chmod(destination, Bitwise.band(mode, 0o777))
        end

      _ ->
        {:error, :invalid_source_tree}
    end
  end

  defp ensure_directory(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:error, :enoent} -> File.mkdir_p(path)
      _ -> {:error, :invalid_source_tree}
    end
  end

  defp regular_or_absent(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:error, :enoent} -> :ok
      _ -> {:error, :invalid_source_tree}
    end
  end

  defp pinned_url?(url) do
    url ==
      "https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp" or
      String.match?(
        url,
        ~r|\Ahttps://codeload\.github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/tar\.gz/[0-9a-f]{40}\z|
      )
  end

  defp cached_or_absent(target, expected) do
    case File.lstat(target) do
      {:error, :enoent} ->
        :ok

      {:ok, %File.Stat{type: :regular, size: size}} when size <= @download_bytes ->
        if digest(target) == {:ok, expected}, do: :ok, else: {:error, :source_hash_mismatch}

      _ ->
        {:error, :invalid_source_download}
    end
  end

  defp download(url, target, expected) do
    temporary = target <> ".download"

    with {:ok, _} <- Application.ensure_all_started(:ssl),
         {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, file} <- File.open(temporary, [:write, :exclusive, :binary]) do
      result =
        try do
          request(url, file)
        rescue
          _ -> {:error, :invalid_source_download}
        after
          File.close(file)
        end

      case result do
        :ok ->
          finish_download(temporary, target, expected)

        error ->
          File.rm(temporary)
          error
      end
    else
      _ -> {:error, :invalid_source_download}
    end
  end

  defp request(url, file) do
    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    options = [timeout: @download_ms, connect_timeout: 15_000, ssl: ssl, autoredirect: false]

    case :httpc.request(:get, {String.to_charlist(url), []}, options,
           sync: false,
           stream: {:self, :once}
         ) do
      {:ok, request_id} ->
        try do
          receive_stream(
            request_id,
            file,
            0,
            System.monotonic_time(:millisecond) + @download_ms,
            nil
          )
        after
          :httpc.cancel_request(request_id)
        end

      _ ->
        {:error, :invalid_source_download}
    end
  end

  defp receive_stream(request_id, file, count, deadline, handler) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:http, {^request_id, :stream_start, _, next_handler}} when is_nil(handler) ->
        :ok = :httpc.stream_next(next_handler)
        receive_stream(request_id, file, count, deadline, next_handler)

      {:http, {^request_id, :stream, bytes}}
      when is_pid(handler) and count + byte_size(bytes) <= @download_bytes ->
        :ok = IO.binwrite(file, bytes)
        :ok = :httpc.stream_next(handler)
        receive_stream(request_id, file, count + byte_size(bytes), deadline, handler)

      {:http, {^request_id, :stream_end, _}} when is_pid(handler) ->
        :ok

      {:http, {^request_id, _}} ->
        {:error, :invalid_source_download}
    after
      remaining -> {:error, :source_download_timeout}
    end
  end

  defp finish_download(temporary, target, expected) do
    if digest(temporary) == {:ok, expected} do
      case File.ln(temporary, target) do
        :ok ->
          File.rm(temporary)

        _ ->
          File.rm(temporary)
          {:error, :invalid_source_download}
      end
    else
      File.rm(temporary)
      {:error, :source_hash_mismatch}
    end
  end

  # GitHub codeload emits one PAX global metadata record. erl_tar applies it
  # before listing/extraction but still exposes the record as :unknown in table/2.
  defp skip_global_header([{~c"pax_global_header", :unknown, size, _, _, _, _} | rest])
       when size in 0..4096,
       do: rest

  defp skip_global_header(entries), do: entries

  defp validate_entries([], _, _), do: {:ok, []}

  defp validate_entries([{name, type, size, _, mode, _, _} | rest], root, total) do
    relative = List.to_string(name)

    if type in [:regular, :directory] and is_integer(size) and size >= 0 and
         is_integer(mode) and total + size <= @archive_bytes and valid_path?(relative, root) do
      case validate_entries(rest, root, total + size) do
        {:ok, admitted} -> {:ok, [{relative, type, mode} | admitted]}
        error -> error
      end
    else
      {:error, :invalid_source_archive}
    end
  end

  defp validate_entries(_, _, _), do: {:error, :invalid_source_archive}

  defp valid_path?(relative, root) do
    parts = String.split(relative, "/", trim: true)

    String.valid?(relative) and Path.type(relative) == :relative and
      parts != [] and hd(parts) == root and
      Enum.all?(parts, &(&1 not in [".", "..", ""])) and
      not String.contains?(relative, <<0>>)
  end

  defp normalize_permissions(destination, {relative, type, mode}) do
    permissions =
      case type do
        :directory -> 0o700
        :regular -> if Bitwise.band(mode, 0o111) == 0, do: 0o644, else: 0o755
      end

    File.chmod!(Path.join(destination, relative), permissions)
  end

  defp empty_directory(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        if File.ls!(path) == [], do: :ok, else: {:error, :nonempty_source_directory}

      {:error, :enoent} ->
        File.mkdir_p(path)

      _ ->
        {:error, :nonempty_source_directory}
    end
  end

  defp patch(sdk, pin, relative, replacements) do
    path = Path.join(sdk, relative)

    with true <- pin["source"] == relative,
         {:ok, before_hash} <- digest(path),
         true <- before_hash == pin["before_sha256"],
         {:ok, original} <- File.read(path),
         {:ok, changed} <- replace_exact(original, replacements),
         true <- sha256(changed) == pin["after_sha256"],
         :ok <- File.write(path, changed) do
      :ok
    else
      _ -> {:error, :unexpected_sdk_source}
    end
  end

  defp replace_exact(bytes, []), do: {:ok, bytes}

  defp replace_exact(bytes, [{before, replacement, count} | rest]) do
    if length(:binary.matches(bytes, before)) == count do
      bytes
      |> String.replace(before, replacement)
      |> replace_exact(rest)
    else
      {:error, :unexpected_sdk_source}
    end
  end

  defp sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
