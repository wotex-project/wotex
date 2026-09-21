defmodule Wotex.Workspace.NativeArtifact.Lease do
  @moduledoc "Exclusive, bounded per-build-identity cache leases."

  alias Wotex.Workspace.NativeArtifact.CanonicalJSON

  @schema "wotex.native-cache-lease@1"
  @digest ~r/^[0-9a-f]{64}$/

  @type t :: %__MODULE__{
          path: Path.t(),
          identity: String.t(),
          token: String.t(),
          expires_at_ms: integer()
        }

  @enforce_keys [:path, :identity, :token, :expires_at_ms]
  defstruct @enforce_keys

  @doc "Acquires one identity lease, waiting no longer than the declared bound."
  @spec acquire(Path.t(), String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def acquire(cache_root, identity, opts \\ []) do
    wait_ms = Keyword.get(opts, :wait_ms, 5_000)
    ttl_ms = Keyword.get(opts, :ttl_ms, 300_000)

    with :ok <- validate_root(cache_root),
         :ok <- validate_identity(identity),
         :ok <- positive_bound(wait_ms, "wait_ms", 60_000),
         :ok <- positive_bound(ttl_ms, "ttl_ms", 86_400_000),
         {:ok, directory} <- lease_directory(cache_root) do
      deadline = System.monotonic_time(:millisecond) + wait_ms
      attempt(directory, identity, ttl_ms, deadline)
    end
  end

  @doc "Checks that the lease token still owns an unexpired exact lease file."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = lease) do
    case read(lease.path) do
      {:ok, record} ->
        record.identity == lease.identity and record.token == lease.token and
          record.expires_at_ms == lease.expires_at_ms and
          record.expires_at_ms > System.system_time(:millisecond)

      {:error, _} ->
        false
    end
  end

  @doc "Releases the exact lease when its on-disk token still matches."
  @spec release(t()) :: :ok | {:error, String.t()}
  def release(%__MODULE__{} = lease) do
    case read(lease.path) do
      {:ok, %{token: token}} when token == lease.token ->
        case File.rm(lease.path) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, reason} -> {:error, "lease release failed: #{:file.format_error(reason)}"}
        end

      {:ok, _} ->
        {:error, "lease ownership was lost"}

      {:error, "lease does not exist"} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns whether an unexpired, valid lease currently protects an identity."
  @spec active?(Path.t(), String.t()) :: boolean()
  def active?(cache_root, identity) do
    path = Path.join([cache_root, "leases", identity <> ".json"])

    case read(path) do
      {:ok, record} ->
        record.identity == identity and record.expires_at_ms > System.system_time(:millisecond)

      {:error, "lease does not exist"} ->
        false

      {:error, _} ->
        File.exists?(path)
    end
  end

  defp attempt(directory, identity, ttl_ms, deadline) do
    path = Path.join(directory, identity <> ".json")
    token = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
    expires_at_ms = System.system_time(:millisecond) + ttl_ms

    record = %{
      "schema" => @schema,
      "identity" => identity,
      "token" => token,
      "expires_at_ms" => expires_at_ms
    }

    case create(path, record) do
      :ok ->
        {:ok,
         %__MODULE__{
           path: path,
           identity: identity,
           token: token,
           expires_at_ms: expires_at_ms
         }}

      {:error, :eexist} ->
        wait_or_break(path, directory, identity, ttl_ms, deadline)

      {:error, reason} ->
        {:error, "lease creation failed: #{:file.format_error(reason)}"}
    end
  end

  defp wait_or_break(path, directory, identity, ttl_ms, deadline) do
    case read(path) do
      {:ok, record} ->
        expired? = record.expires_at_ms <= System.system_time(:millisecond)

        if record.identity == identity and expired? do
          break_stale(path, record, directory)
        else
          :wait
        end

      {:error, "lease does not exist"} ->
        :retry

      {:error, reason} ->
        {:error, reason}
    end
    |> then(fn
      :wait -> wait(directory, identity, ttl_ms, deadline)
      :retry -> attempt(directory, identity, ttl_ms, deadline)
      :broken -> attempt(directory, identity, ttl_ms, deadline)
      {:error, _} = error -> error
    end)
  end

  defp wait(directory, identity, ttl_ms, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, "timed out waiting for native cache lease #{identity}"}
    else
      Process.sleep(min(remaining, 25))
      attempt(directory, identity, ttl_ms, deadline)
    end
  end

  defp break_stale(path, record, directory) do
    tombstone =
      Path.join(
        directory,
        ".stale-#{record.identity}-#{System.unique_integer([:positive, :monotonic])}"
      )

    case File.rename(path, tombstone) do
      :ok ->
        result =
          case read(tombstone) do
            {:ok, moved}
            when moved.token == record.token and moved.expires_at_ms == record.expires_at_ms ->
              File.rm(tombstone)

            _ ->
              {:error, "stale lease changed while it was being retired"}
          end

        case result do
          :ok ->
            :broken

          {:error, reason} when is_atom(reason) ->
            {:error, "stale lease retirement failed: #{:file.format_error(reason)}"}

          {:error, _} = error ->
            error
        end

      {:error, :enoent} ->
        :retry

      {:error, reason} ->
        {:error, "stale lease retirement failed: #{:file.format_error(reason)}"}
    end
  end

  defp create(path, record) do
    candidate = Path.join(Path.dirname(path), ".candidate-#{record["token"]}")

    case File.open(candidate, [:write, :binary, :exclusive]) do
      {:ok, io} ->
        result =
          case File.chmod(candidate, 0o600) do
            :ok ->
              :ok = IO.binwrite(io, CanonicalJSON.encode!(record) <> "\n")
              :file.sync(io)

            {:error, _} = error ->
              error
          end

        File.close(io)

        if result == :ok do
          link_candidate(candidate, path)
        else
          File.rm(candidate)
          result
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp link_candidate(candidate, path) do
    result = File.ln(candidate, path)
    _ = File.rm(candidate)
    result
  end

  defp read(path) do
    with {:ok, bytes} <- File.read(path),
         true <- byte_size(bytes) <= 4_096 or {:error, "lease record exceeds 4096 bytes"},
         {:ok, map} <- decode(bytes),
         :ok <- exact_record(map) do
      {:ok,
       %__MODULE__{
         path: path,
         identity: map["identity"],
         token: map["token"],
         expires_at_ms: map["expires_at_ms"]
       }}
    else
      {:error, :enoent} ->
        {:error, "lease does not exist"}

      {:error, reason} when is_atom(reason) ->
        {:error, "lease read failed: #{:file.format_error(reason)}"}

      {:error, _} = error ->
        error

      false ->
        {:error, "invalid lease record"}
    end
  end

  defp decode(bytes) do
    case JSON.decode(bytes) do
      {:ok, map} -> {:ok, map}
      {:error, error} -> {:error, "invalid lease JSON: #{Exception.message(error)}"}
    end
  rescue
    error -> {:error, "invalid lease JSON: #{Exception.message(error)}"}
  end

  defp exact_record(map) when is_map(map) do
    if Enum.sort(Map.keys(map)) == Enum.sort(~w(schema identity token expires_at_ms)) and
         map["schema"] == @schema and valid_identity?(map["identity"]) and
         is_binary(map["token"]) and byte_size(map["token"]) in 16..128 and
         is_integer(map["expires_at_ms"]) do
      :ok
    else
      {:error, "invalid lease record"}
    end
  end

  defp exact_record(_), do: {:error, "invalid lease record"}

  defp lease_directory(cache_root) do
    directory = Path.join(cache_root, "leases")

    with :ok <- ensure_directory(directory),
         :ok <- File.chmod(directory, 0o700) do
      {:ok, directory}
    end
  end

  defp ensure_directory(directory) do
    case File.mkdir(directory) do
      :ok -> :ok
      {:error, :eexist} -> ordinary_directory(directory)
      {:error, reason} -> {:error, "lease directory: #{:file.format_error(reason)}"}
    end
  end

  defp ordinary_directory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} -> :ok
      {:ok, %{type: type}} -> {:error, "lease directory is #{type}, expected directory"}
      {:error, reason} -> {:error, "lease directory: #{:file.format_error(reason)}"}
    end
  end

  defp validate_root(root) do
    if is_binary(root) and Path.type(root) == :absolute,
      do: ordinary_cache_root(root),
      else: {:error, "cache root must be absolute"}
  end

  defp ordinary_cache_root(root) do
    case File.lstat(root) do
      {:ok, %{type: :directory}} -> :ok
      {:ok, %{type: type}} -> {:error, "cache root is #{type}, expected directory"}
      {:error, reason} -> {:error, "cache root: #{:file.format_error(reason)}"}
    end
  end

  defp validate_identity(identity) do
    if valid_identity?(identity),
      do: :ok,
      else: {:error, "cache identity must be a full lowercase SHA-256"}
  end

  defp valid_identity?(identity), do: is_binary(identity) and Regex.match?(@digest, identity)

  defp positive_bound(value, _, maximum)
       when is_integer(value) and value > 0 and value <= maximum,
       do: :ok

  defp positive_bound(_, name, maximum),
    do: {:error, "#{name} must be an integer from 1 through #{maximum}"}
end
