defmodule Wotex.BLE.Native.Source do
  @moduledoc """
  Reads native source pins and transfers, hashes and extracts pinned archives.

  This helper is used only by an explicit native build. Dependency loading and
  compilation perform no download or filesystem work. Downloads use HTTPS with
  peer and host verification, a finite byte and time budget, no redirect and an
  exact SHA-256 check before the archive becomes visible at its target path.

  Archive admission accepts only regular files and directories below the exact
  pinned root. Links, device files, traversal, empty names and oversized trees
  fail before extraction. Extracted directories become private and file modes
  retain only the executable bit. Content identity is not a license or advisory
  review.
  """

  @download_bytes 8 * 1024 * 1024
  @download_ms 120_000
  @connect_ms 15_000
  @archive_files 4096
  @archive_bytes 128 * 1024 * 1024
  @maximum_pins 65_536

  @typedoc "One verified download pin from the packaged native dependency file."
  @type pin :: %{
          required(String.t()) => String.t()
        }

  @doc "Returns the named download pin after validating its exact field set and HTTPS source."
  @spec pin(term(), term()) :: {:ok, pin()} | {:error, :invalid_native_pins}
  def pin(native, name) when is_binary(native) and is_binary(name) do
    file = Path.join(native, "dependencies.json")

    with {:ok, %File.Stat{type: :regular, size: size}} when size <= @maximum_pins <-
           File.lstat(file),
         {:ok, bytes} <- File.read(file),
         {:ok, %{"schema" => "wotex.native-sources", "version" => 1, "downloads" => downloads}}
         when is_list(downloads) <- Jason.decode(bytes),
         [pin] <- Enum.filter(downloads, &(is_map(&1) and &1["name"] == name)),
         true <- valid_pin?(pin) do
      {:ok, pin}
    else
      _ -> {:error, :invalid_native_pins}
    end
  end

  def pin(_, _), do: {:error, :invalid_native_pins}

  @typedoc "A download failure before the archive becomes visible at its target."
  @type download_error ::
          :invalid_source_download
          | :source_download_limit
          | :source_download_timeout
          | :source_hash_mismatch

  @doc "Downloads one pinned archive to an absent absolute target and verifies its digest."
  @spec fetch(term(), term()) :: :ok | {:error, download_error()}
  def fetch(%{"url" => url, "sha256" => expected} = pin, target) when is_binary(target) do
    if valid_pin?(pin),
      do: transfer(url, target, expected, cacerts: :public_key.cacerts_get()),
      else: {:error, :invalid_source_download}
  end

  def fetch(_, _), do: {:error, :invalid_source_download}

  @doc false
  @spec transfer(String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, download_error()}
  def transfer(url, target, expected, options) do
    bytes = Keyword.get(options, :bytes, @download_bytes)
    timeout = Keyword.get(options, :timeout_ms, @download_ms)

    with true <- String.starts_with?(url, "https://") and Path.type(target) == :absolute,
         true <- String.match?(expected, ~r/\A[0-9a-f]{64}\z/),
         {:error, :enoent} <- File.lstat(target) do
      download(url, target, expected, {Keyword.fetch!(options, :cacerts), bytes, timeout})
    else
      _ -> {:error, :invalid_source_download}
    end
  end

  @doc "Returns the lowercase SHA-256 digest of one regular file."
  @spec digest(term()) :: {:ok, String.t()} | {:error, :invalid_source_file}
  def digest(path) when is_binary(path) do
    with {:ok, %File.Stat{type: :regular}} <- File.lstat(path),
         {:ok, file} <- File.open(path, [:read, :binary, :raw]) do
      try do
        digest = hash_file(file, :crypto.hash_init(:sha256))
        {:ok, Base.encode16(digest, case: :lower)}
      after
        File.close(file)
      end
    else
      _ -> {:error, :invalid_source_file}
    end
  end

  def digest(_), do: {:error, :invalid_source_file}

  @doc "Returns relative regular-file paths and digests; links and special files fail."
  @spec file_hashes(term()) :: {:ok, %{String.t() => String.t()}} | {:error, :invalid_source_tree}
  def file_hashes(path) when is_binary(path) do
    with {:ok, %File.Stat{type: :directory}} <- File.lstat(path),
         {:ok, files} <- tree_files(path, "") do
      Enum.reduce_while(Enum.sort(files), {:ok, %{}}, fn relative, {:ok, hashes} ->
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

  @doc "Hashes a regular-file tree in sorted relative-path order."
  @spec tree_digest(term()) :: {:ok, String.t()} | {:error, :invalid_source_tree}
  def tree_digest(path) do
    with {:ok, hashes} <- file_hashes(path) do
      context =
        Enum.reduce(hashes, :crypto.hash_init(:sha256), fn {relative, hash}, context ->
          :crypto.hash_update(context, ["file", 0, relative, 0, hash, 0])
        end)

      {:ok, Base.encode16(:crypto.hash_final(context), case: :lower)}
    end
  end

  @doc "Lists an uncompressed tar archive and admits only its finite pinned root tree."
  @spec validate_archive(term(), term()) :: {:ok, list()} | {:error, :invalid_source_archive}
  def validate_archive(path, root) when is_binary(path) and is_binary(root) do
    with {:ok, %File.Stat{type: :regular, size: size}} when size <= @archive_bytes <-
           File.lstat(path),
         {:ok, entries} when length(entries) <= @archive_files <-
           :erl_tar.table(String.to_charlist(path), [:verbose]) do
      entries(entries, root, 0, [])
    else
      _ -> {:error, :invalid_source_archive}
    end
  end

  def validate_archive(_, _), do: {:error, :invalid_source_archive}

  @doc "Extracts a validated archive into an absent or empty absolute destination."
  @spec extract(term(), term(), term()) :: :ok | {:error, :invalid_source_archive}
  def extract(archive, destination, root) when is_binary(destination) do
    with true <- Path.type(destination) == :absolute,
         {:ok, _} <- validate_archive(archive, root),
         :ok <- empty_directory(destination),
         :ok <-
           :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(destination)) do
      private_modes(Path.join(destination, root))
    else
      _ -> {:error, :invalid_source_archive}
    end
  end

  def extract(_, _, _), do: {:error, :invalid_source_archive}

  defp valid_pin?(pin) do
    map_size(pin) == 7 and
      Enum.all?(~w(name version url sha256 root license license_path), &is_binary(pin[&1])) and
      String.starts_with?(pin["url"], "https://dbus.freedesktop.org/releases/dbus/") and
      String.match?(pin["sha256"], ~r/\A[0-9a-f]{64}\z/) and
      String.match?(pin["root"], ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/)
  end

  defp download(url, target, expected, limits) do
    temporary = target <> ".download"

    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl),
         {:ok, file} <- File.open(temporary, [:write, :exclusive, :binary, :raw]) do
      result =
        try do
          request(url, file, limits)
        after
          File.close(file)
        end

      finish(result, temporary, target, expected)
    else
      _ -> {:error, :invalid_source_download}
    end
  end

  defp request(url, file, {cacerts, bytes, timeout}) do
    ssl = [
      verify: :verify_peer,
      cacerts: cacerts,
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    # The receive deadline below governs the transfer; the client timeout is a backstop.
    options = [
      timeout: timeout + @connect_ms,
      connect_timeout: @connect_ms,
      ssl: ssl,
      autoredirect: false
    ]

    stream = [sync: false, stream: {:self, :once}, body_format: :binary]

    case :httpc.request(:get, {String.to_charlist(url), []}, options, stream) do
      {:ok, request} ->
        try do
          deadline = System.monotonic_time(:millisecond) + timeout
          receive_body(request, file, {0, bytes}, deadline, nil)
        after
          :httpc.cancel_request(request)
        end

      _ ->
        {:error, :invalid_source_download}
    end
  end

  defp receive_body(request, file, {count, limit} = budget, deadline, handler) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:http, {^request, :stream_start, _, next}} when is_nil(handler) and is_pid(next) ->
        :ok = :httpc.stream_next(next)
        receive_body(request, file, budget, deadline, next)

      {:http, {^request, :stream, bytes}}
      when is_pid(handler) and count + byte_size(bytes) <= limit ->
        :ok = :file.write(file, bytes)
        :ok = :httpc.stream_next(handler)
        receive_body(request, file, {count + byte_size(bytes), limit}, deadline, handler)

      {:http, {^request, :stream_end, _}} when is_pid(handler) ->
        :ok

      {:http, {^request, _}} ->
        {:error, :invalid_source_download}

      {:http, {^request, :stream, _}} ->
        {:error, :source_download_limit}
    after
      remaining -> {:error, :source_download_timeout}
    end
  end

  defp finish(:ok, temporary, target, expected) do
    with {:ok, ^expected} <- digest(temporary),
         :ok <- File.rename(temporary, target) do
      :ok
    else
      _ ->
        File.rm(temporary)
        {:error, :source_hash_mismatch}
    end
  end

  defp finish(error, temporary, _, _) do
    File.rm(temporary)
    error
  end

  defp hash_file(file, context) do
    case :file.read(file, 1_048_576) do
      {:ok, bytes} -> hash_file(file, :crypto.hash_update(context, bytes))
      :eof -> :crypto.hash_final(context)
    end
  end

  defp tree_files(root, relative) do
    case File.ls(Path.join(root, relative)) do
      {:ok, names} ->
        Enum.reduce_while(names, {:ok, []}, fn name, {:ok, files} ->
          case tree_entry(root, join(relative, name)) do
            {:ok, found} -> {:cont, {:ok, found ++ files}}
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

  defp join("", name), do: name
  defp join(relative, name), do: relative <> "/" <> name

  defp entries([], _, _, admitted), do: {:ok, Enum.reverse(admitted)}

  defp entries([{name, type, size, _, mode, _, _} | rest], root, total, admitted)
       when type in [:regular, :directory] and is_integer(size) and size >= 0 and
              is_integer(mode) do
    relative = List.to_string(name)

    if total + size <= @archive_bytes and archive_path?(relative, root),
      do: entries(rest, root, total + size, [{relative, type, mode} | admitted]),
      else: {:error, :invalid_source_archive}
  end

  defp entries(_, _, _, _), do: {:error, :invalid_source_archive}

  defp archive_path?(relative, root) do
    parts = String.split(relative, "/", trim: true)

    String.valid?(relative) and byte_size(relative) <= 4096 and
      Path.type(relative) == :relative and parts != [] and hd(parts) == root and
      Enum.all?(parts, &(&1 not in [".", ".."])) and not String.contains?(relative, [<<0>>, "\\"])
  end

  defp empty_directory(path) do
    case File.lstat(path) do
      {:error, :enoent} -> File.mkdir_p(path)
      {:ok, %File.Stat{type: :directory}} -> if File.ls(path) == {:ok, []}, do: :ok, else: :error
      _ -> :error
    end
  end

  # Archive admission already excluded links and special files, including
  # directories that the archive creates implicitly for its file entries.
  defp private_modes(path) do
    case File.lstat!(path) do
      %File.Stat{type: :directory} ->
        File.chmod!(path, 0o700)
        Enum.each(File.ls!(path), &private_modes(Path.join(path, &1)))

      %File.Stat{type: :regular, mode: mode} ->
        File.chmod!(path, if(Bitwise.band(mode, 0o111) == 0, do: 0o600, else: 0o700))
    end
  end
end
