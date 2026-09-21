defmodule Wotex.Workspace.NativeArtifact.Cache do
  @moduledoc """
  Verified local native artifact cache adoption and exact-entry maintenance.

  Adoption always stages beside the final identity directory, verifies the
  extracted tree, checks the active lease, and installs with one rename.
  Existing invalid entries are never overwritten implicitly.
  """

  alias Wotex.Workspace.NativeArtifact.Archive
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.Lease
  alias Wotex.Workspace.NativeArtifact.PayloadManifest
  alias Wotex.Workspace.NativeArtifact.Verifier

  @schema "wotex.native-cache-entry@1"
  @digest ~r/^[0-9a-f]{64}$/
  @metadata_fields ~w(schema build_identity payload_identity package profile target transport_sha256 transport_size manifest_schema artifact_format)

  defmodule Entry do
    @moduledoc "One fully verified canonical cache entry."

    @enforce_keys [:path, :manifest, :transport_sha256, :transport_size, :reused]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            path: Path.t(),
            manifest: PayloadManifest.t(),
            transport_sha256: String.t(),
            transport_size: non_neg_integer(),
            reused: boolean()
          }
  end

  @doc "Verifies and atomically adopts one local archive under its full build identity."
  @spec adopt(Path.t(), Descriptor.t(), String.t(), String.t(), Path.t(), keyword()) ::
          {:ok, Entry.t()} | {:error, [String.t()]}
  def adopt(archive, descriptor, target, build_identity, cache_root, opts \\ []) do
    limits = Keyword.get(opts, :limits, %Archive.Limits{})

    lease_opts = [
      wait_ms: Keyword.get(opts, :lease_wait_ms, 5_000),
      ttl_ms: Keyword.get(opts, :lease_ttl_ms, 300_000)
    ]

    with :ok <- wrap_one(prepare_root(cache_root)),
         {:ok, verified} <- Verifier.verify(archive, descriptor, target, build_identity, limits),
         {:ok, lease} <- wrap(Lease.acquire(cache_root, build_identity, lease_opts)) do
      try do
        adopt_under_lease(
          archive,
          descriptor,
          target,
          build_identity,
          cache_root,
          verified,
          lease,
          limits
        )
      after
        _ = Lease.release(lease)
      end
    end
  end

  @doc "Validates one exact cache entry against current descriptor and target admission."
  @spec inspect(Path.t(), String.t(), Descriptor.t(), String.t()) ::
          {:ok, Entry.t()} | {:error, [String.t()]}
  def inspect(cache_root, build_identity, descriptor, target) do
    with :ok <- wrap_one(validate_root(cache_root)),
         :ok <- wrap_one(validate_objects(cache_root)),
         :ok <- wrap_one(validate_identity(build_identity)) do
      path = entry_path(cache_root, build_identity)
      validate_entry(path, build_identity, descriptor, target, false)
    end
  end

  @doc "Deletes one exact cache-owned identity and never follows symlinks."
  @spec delete(Path.t(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def delete(cache_root, build_identity, opts \\ []) do
    lease_opts = [
      wait_ms: Keyword.get(opts, :lease_wait_ms, 250),
      ttl_ms: Keyword.get(opts, :lease_ttl_ms, 30_000)
    ]

    with :ok <- validate_root(cache_root),
         :ok <- validate_objects(cache_root),
         :ok <- validate_identity(build_identity),
         {:ok, lease} <- Lease.acquire(cache_root, build_identity, lease_opts) do
      try do
        delete_under_lease(cache_root, build_identity)
      after
        _ = Lease.release(lease)
      end
    else
      {:error, _} = error -> error
    end
  end

  defp delete_under_lease(cache_root, build_identity) do
    path = entry_path(cache_root, build_identity)

    with {:ok, _} <- owned_metadata(path, build_identity) do
      remove_tree(path)
    end
  end

  @doc "Removes a bounded number of exact cache-owned entries not in the keep set."
  @spec garbage_collect(Path.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def garbage_collect(cache_root, opts \\ []) do
    keep = MapSet.new(Keyword.get(opts, :keep, []))
    max_scan = Keyword.get(opts, :max_scan, 256)
    max_remove = Keyword.get(opts, :max_remove, 32)

    with :ok <- validate_root(cache_root),
         :ok <- validate_keep(keep),
         :ok <- positive(max_scan, "max_scan", 10_000),
         :ok <- positive(max_remove, "max_remove", 1_000),
         {:ok, names} <- list_objects(cache_root) do
      candidates =
        names
        |> Enum.sort()
        |> Enum.take(max_scan)

      {removed, retained, skipped} =
        collect_candidates(candidates, cache_root, keep, max_remove)

      {:ok,
       %{
         scanned: length(candidates),
         removed: Enum.sort(removed),
         retained: Enum.sort(retained),
         skipped: Enum.sort(skipped)
       }}
    end
  end

  defp collect_candidates(candidates, cache_root, keep, max_remove) do
    Enum.reduce(candidates, {[], [], []}, fn name, accumulator ->
      collect_candidate(name, accumulator, cache_root, keep, max_remove)
    end)
  end

  defp collect_candidate(name, {removed, retained, skipped} = accumulator, cache_root, keep, limit) do
    cond do
      length(removed) >= limit ->
        accumulator

      MapSet.member?(keep, name) or Lease.active?(cache_root, name) ->
        {removed, [name | retained], skipped}

      true ->
        remove_owned_candidate(name, removed, retained, skipped, cache_root)
    end
  end

  defp remove_owned_candidate(name, removed, retained, skipped, cache_root) do
    path = entry_path(cache_root, name)

    with {:ok, _} <- owned_metadata(path, name),
         :ok <- delete(cache_root, name, lease_wait_ms: 1) do
      {[name | removed], retained, skipped}
    else
      {:error, _} -> {removed, retained, [name | skipped]}
    end
  end

  defp adopt_under_lease(
         archive,
         descriptor,
         target,
         build_identity,
         cache_root,
         verified,
         lease,
         limits
       ) do
    final = entry_path(cache_root, build_identity)

    case validate_entry(final, build_identity, descriptor, target, true) do
      {:ok, entry} ->
        {:ok, %{entry | reused: true}}

      {:error, ["cache entry does not exist"]} ->
        stage_and_install(
          archive,
          descriptor,
          target,
          build_identity,
          cache_root,
          final,
          verified,
          lease,
          limits
        )

      {:error, errors} ->
        {:error, ["existing cache entry is invalid" | errors]}
    end
  end

  defp stage_and_install(
         archive,
         descriptor,
         target,
         build_identity,
         cache_root,
         final,
         verified,
         lease,
         limits
       ) do
    objects = objects_path(cache_root)
    stage = Path.join(objects, ".#{build_identity}.stage-#{lease.token}")

    result =
      with :ok <- mkdir_private(stage),
           {:ok, archive_copy} <- copy_verified_archive(archive, stage, verified, limits),
           {:ok, payload} <- extract(archive_copy, stage),
           :ok <- validate_staging(payload, verified.manifest, descriptor, target, build_identity),
           :ok <- write_metadata(stage, verified),
           true <-
             Lease.valid?(lease) or {:error, "cache lease expired or was lost before adoption"},
           :ok <- rename_install(stage, final) do
        {:ok,
         %Entry{
           path: final,
           manifest: verified.manifest,
           transport_sha256: verified.transport_sha256,
           transport_size: verified.compressed_size,
           reused: false
         }}
      else
        {:error, errors} when is_list(errors) -> {:error, errors}
        {:error, message} -> {:error, [message]}
      end

    unless match?({:ok, _}, result), do: remove_private_stage(stage)
    result
  end

  defp validate_entry(path, build_identity, descriptor, target, reused) do
    case File.lstat(path) do
      {:error, :enoent} ->
        {:error, ["cache entry does not exist"]}

      {:ok, %{type: :directory}} ->
        with {:ok, metadata} <- wrap(owned_metadata(path, build_identity)),
             {:ok, manifest} <- read_manifest(Path.join([path, "payload", Archive.manifest_path()])),
             {:ok, actual_entries} <-
               wrap(
                 PayloadManifest.scan_tree(Path.join(path, "payload"), [Archive.manifest_path()])
               ),
             :ok <-
               Verifier.validate_entries(
                 manifest,
                 actual_entries,
                 descriptor,
                 target,
                 build_identity
               ),
             :ok <- metadata_matches(metadata, manifest),
             :ok <- archive_matches(path, metadata) do
          {:ok,
           %Entry{
             path: path,
             manifest: manifest,
             transport_sha256: metadata["transport_sha256"],
             transport_size: metadata["transport_size"],
             reused: reused
           }}
        end

      {:ok, %{type: type}} ->
        {:error, ["cache entry is #{type}, expected directory"]}

      {:error, reason} ->
        {:error, ["cache entry: #{:file.format_error(reason)}"]}
    end
  end

  defp validate_staging(payload, manifest, descriptor, target, build_identity) do
    with {:ok, staged_manifest} <- read_manifest(Path.join(payload, Archive.manifest_path())),
         true <-
           staged_manifest == manifest or
             {:error, ["extracted manifest differs from verified manifest"]},
         {:ok, entries} <- wrap(PayloadManifest.scan_tree(payload, [Archive.manifest_path()])) do
      Verifier.validate_entries(manifest, entries, descriptor, target, build_identity)
    end
  end

  defp copy_verified_archive(source, stage, verified, limits) do
    destination = Path.join(stage, "artifact.tar")

    case File.open(source, [:read, :binary]) do
      {:ok, input} ->
        try do
          open_staged_archive(input, destination, verified, limits)
        after
          File.close(input)
        end

      {:error, reason} ->
        {:error, "artifact staging failed: #{:file.format_error(reason)}"}
    end
  end

  defp open_staged_archive(input, destination, verified, limits) do
    case File.open(destination, [:write, :binary, :exclusive]) do
      {:ok, output} ->
        try do
          verify_staged_copy(input, output, destination, verified, limits)
        after
          File.close(output)
        end

      {:error, reason} ->
        {:error, "artifact staging failed: #{:file.format_error(reason)}"}
    end
  end

  defp verify_staged_copy(input, output, destination, verified, limits) do
    case copy_chunks(input, output, :crypto.hash_init(:sha256), 0, limits.compressed_bytes) do
      {:ok, digest, size} ->
        cond do
          size != verified.compressed_size ->
            {:error, "artifact changed size after verification"}

          digest != verified.transport_sha256 ->
            {:error, "artifact changed content after verification"}

          true ->
            with :ok <- :file.sync(output),
                 :ok <- File.chmod(destination, 0o600) do
              {:ok, destination}
            end
        end

      {:error, _} = error ->
        error
    end
  end

  defp copy_chunks(input, output, digest, size, maximum) do
    case IO.binread(input, 65_536) do
      :eof ->
        raw_digest = :crypto.hash_final(digest)
        {:ok, Base.encode16(raw_digest, case: :lower), size}

      {:error, reason} ->
        {:error, "artifact read failed: #{:file.format_error(reason)}"}

      bytes when size + byte_size(bytes) > maximum ->
        {:error, "artifact changed beyond the compressed-byte bound"}

      bytes ->
        :ok = IO.binwrite(output, bytes)

        copy_chunks(
          input,
          output,
          :crypto.hash_update(digest, bytes),
          size + byte_size(bytes),
          maximum
        )
    end
  end

  defp extract(archive, stage) do
    payload = Path.join(stage, "payload")

    with :ok <- mkdir_private(payload),
         {:ok, encoding} <- archive_encoding(archive),
         :ok <- extract_tar(archive, payload, encoding) do
      {:ok, payload}
    end
  end

  defp extract_tar(archive, payload, encoding) do
    options = [{:cwd, String.to_charlist(payload)}]
    options = if encoding == :gzip, do: [:compressed | options], else: options

    case :erl_tar.extract(String.to_charlist(archive), options) do
      :ok -> :ok
      {:error, reason} -> {:error, "verified archive extraction failed: #{inspect(reason)}"}
    end
  end

  defp archive_encoding(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        result =
          case IO.binread(io, 2) do
            <<0x1F, 0x8B>> -> {:ok, :gzip}
            bytes when is_binary(bytes) -> {:ok, :tar}
            :eof -> {:error, "verified archive became empty"}
            {:error, reason} -> {:error, "artifact staging failed: #{:file.format_error(reason)}"}
          end

        File.close(io)
        result

      {:error, reason} ->
        {:error, "artifact staging failed: #{:file.format_error(reason)}"}
    end
  end

  defp write_metadata(stage, verified) do
    manifest = verified.manifest

    metadata = %{
      "schema" => @schema,
      "build_identity" => manifest.build_identity,
      "payload_identity" => manifest.payload_identity,
      "package" => manifest.package,
      "profile" => manifest.profile,
      "target" => manifest.target,
      "transport_sha256" => verified.transport_sha256,
      "transport_size" => verified.compressed_size,
      "manifest_schema" => PayloadManifest.schema(),
      "artifact_format" => "wotex.native-artifact@1"
    }

    path = Path.join(stage, "cache-entry.json")

    case File.write(path, CanonicalJSON.encode!(metadata) <> "\n", [:binary, :exclusive]) do
      :ok -> File.chmod(path, 0o600)
      {:error, _} = error -> error
    end
  end

  defp owned_metadata(path, identity) do
    metadata_path = Path.join(path, "cache-entry.json")

    with {:ok, %{type: :directory}} <- File.lstat(path),
         {:ok, bytes} <- read_bounded_regular(metadata_path, "cache metadata", 16_384),
         {:ok, map} <- decode(bytes),
         :ok <- validate_metadata(map, identity) do
      {:ok, map}
    else
      {:ok, %{type: type}} ->
        {:error, "cache entry is #{type}, expected directory"}

      {:error, :enoent} ->
        {:error, "cache entry does not exist"}

      {:error, reason} when is_atom(reason) ->
        {:error, "cache metadata: #{:file.format_error(reason)}"}

      {:error, _} = error ->
        error
    end
  end

  defp validate_metadata(map, identity) when is_map(map) do
    with :ok <- exact_metadata_fields(map),
         :ok <- admitted_metadata_schema(map),
         :ok <- addressed_identity(map, identity),
         :ok <- metadata_digests(map),
         :ok <- metadata_transport_size(map),
         :ok <- admitted_metadata_format(map) do
      metadata_names(map)
    end
  end

  defp validate_metadata(_, _), do: {:error, "cache metadata must be an object"}

  defp exact_metadata_fields(map) do
    if Enum.sort(Map.keys(map)) == Enum.sort(@metadata_fields),
      do: :ok,
      else: {:error, "cache metadata fields are not the closed schema"}
  end

  defp admitted_metadata_schema(%{"schema" => @schema}), do: :ok
  defp admitted_metadata_schema(_), do: {:error, "unknown cache metadata schema"}

  defp addressed_identity(%{"build_identity" => identity}, identity), do: :ok

  defp addressed_identity(_, _),
    do: {:error, "cache metadata build identity does not match its address"}

  defp metadata_digests(map) do
    if valid_digest?(map["payload_identity"]) and valid_digest?(map["transport_sha256"]),
      do: :ok,
      else: {:error, "cache metadata contains an invalid digest"}
  end

  defp metadata_transport_size(%{"transport_size" => size})
       when is_integer(size) and size >= 0,
       do: :ok

  defp metadata_transport_size(_),
    do: {:error, "cache metadata contains an invalid transport size"}

  defp admitted_metadata_format(map) do
    if map["manifest_schema"] == PayloadManifest.schema() and
         map["artifact_format"] == "wotex.native-artifact@1",
       do: :ok,
       else: {:error, "cache metadata format is not admitted"}
  end

  defp metadata_names(map) do
    if Enum.all?(~w(package profile target), &(is_binary(map[&1]) and map[&1] != "")),
      do: :ok,
      else: {:error, "cache metadata identity fields are invalid"}
  end

  defp metadata_matches(metadata, manifest) do
    fields = [
      {"package", manifest.package},
      {"profile", manifest.profile},
      {"target", manifest.target},
      {"build_identity", manifest.build_identity},
      {"payload_identity", manifest.payload_identity}
    ]

    case Enum.find(fields, fn {field, expected} -> metadata[field] != expected end) do
      nil ->
        :ok

      {field, expected} ->
        {:error, ["cache metadata #{field} mismatch; expected #{inspect(expected)}"]}
    end
  end

  defp archive_matches(path, metadata) do
    archive = Path.join(path, "artifact.tar")

    with {:ok, %{type: :regular, size: size}} <- File.lstat(archive),
         true <- size == metadata["transport_size"] or {:error, "cached archive size mismatch"},
         {:ok, digest} <- hash_file(archive),
         true <-
           digest == metadata["transport_sha256"] or {:error, "cached archive digest mismatch"} do
      :ok
    else
      {:ok, %{type: type}} ->
        {:error, ["cached archive is #{type}, expected regular file"]}

      {:error, reason} when is_atom(reason) ->
        {:error, ["cached archive: #{:file.format_error(reason)}"]}

      {:error, reason} ->
        {:error, [reason]}

      false ->
        {:error, ["cached archive mismatch"]}
    end
  end

  defp hash_file(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        result = hash_chunks(io, :crypto.hash_init(:sha256))
        File.close(io)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hash_chunks(io, digest) do
    case IO.binread(io, 65_536) do
      :eof ->
        raw_digest = :crypto.hash_final(digest)
        {:ok, Base.encode16(raw_digest, case: :lower)}

      {:error, reason} ->
        {:error, reason}

      bytes ->
        hash_chunks(io, :crypto.hash_update(digest, bytes))
    end
  end

  defp read_manifest(path) do
    with {:ok, bytes} <- read_bounded_regular(path, "payload manifest", 1_048_576),
         {:ok, manifest} <- PayloadManifest.decode(bytes) do
      {:ok, manifest}
    else
      {:error, reason} ->
        {:error, [reason]}
    end
  end

  defp rename_install(stage, final) do
    case File.rename(stage, final) do
      :ok -> :ok
      {:error, :eexist} -> {:error, "cache entry appeared while the lease was held"}
      {:error, reason} -> {:error, "cache adoption rename failed: #{:file.format_error(reason)}"}
    end
  end

  defp prepare_root(cache_root) do
    with :ok <- absolute_root(cache_root),
         :ok <- File.mkdir_p(cache_root),
         {:ok, %{type: :directory}} <- File.lstat(cache_root),
         :ok <- File.chmod(cache_root, 0o700),
         :ok <- ensure_private_directory(objects_path(cache_root), "cache objects") do
      :ok
    else
      {:ok, %{type: type}} -> {:error, "cache root is #{type}, expected directory"}
      {:error, reason} when is_atom(reason) -> {:error, "cache root: #{:file.format_error(reason)}"}
      {:error, _} = error -> error
    end
  end

  defp validate_root(cache_root) do
    with :ok <- absolute_root(cache_root),
         {:ok, %{type: :directory}} <- File.lstat(cache_root) do
      :ok
    else
      {:ok, %{type: type}} -> {:error, "cache root is #{type}, expected directory"}
      {:error, reason} when is_atom(reason) -> {:error, "cache root: #{:file.format_error(reason)}"}
      {:error, _} = error -> error
    end
  end

  defp validate_objects(cache_root) do
    case File.lstat(objects_path(cache_root)) do
      {:ok, %{type: :directory}} -> :ok
      {:ok, %{type: type}} -> {:error, "cache objects is #{type}, expected directory"}
      {:error, reason} -> {:error, "cache objects: #{:file.format_error(reason)}"}
    end
  end

  defp absolute_root(root) do
    if is_binary(root) and Path.type(root) == :absolute,
      do: :ok,
      else: {:error, "cache root must be absolute"}
  end

  defp mkdir_private(path) do
    with :ok <- File.mkdir(path),
         :ok <- File.chmod(path, 0o700) do
      :ok
    else
      {:error, reason} -> {:error, "staging directory: #{:file.format_error(reason)}"}
    end
  end

  defp ensure_private_directory(path, label) do
    case File.mkdir(path) do
      :ok -> File.chmod(path, 0o700)
      {:error, :eexist} -> validate_private_directory(path, label)
      {:error, reason} -> {:error, "#{label}: #{:file.format_error(reason)}"}
    end
  end

  defp validate_private_directory(path, label) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} -> File.chmod(path, 0o700)
      {:ok, %{type: type}} -> {:error, "#{label} is #{type}, expected directory"}
      {:error, reason} -> {:error, "#{label}: #{:file.format_error(reason)}"}
    end
  end

  defp remove_private_stage(stage) do
    if String.contains?(Path.basename(stage), ".stage-") do
      _ = remove_tree(stage)
    end
  end

  defp remove_tree(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        with {:ok, names} <- File.ls(path),
             :ok <- remove_children(path, names) do
          case File.rmdir(path) do
            :ok ->
              :ok

            {:error, reason} ->
              {:error, "cannot remove cache directory: #{:file.format_error(reason)}"}
          end
        end

      {:ok, _} ->
        case File.rm(path) do
          :ok -> :ok
          {:error, reason} -> {:error, "cannot remove cache file: #{:file.format_error(reason)}"}
        end

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, "cannot inspect cache path: #{:file.format_error(reason)}"}
    end
  end

  defp remove_children(parent, names) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      case remove_tree(Path.join(parent, name)) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp list_objects(cache_root) do
    path = objects_path(cache_root)

    case File.lstat(path) do
      {:error, :enoent} -> {:ok, []}
      {:ok, %{type: :directory}} -> list_object_names(path)
      {:ok, %{type: type}} -> {:error, "cache objects is #{type}, expected directory"}
      {:error, reason} -> {:error, "cache objects: #{:file.format_error(reason)}"}
    end
  end

  defp list_object_names(path) do
    case File.ls(path) do
      {:ok, names} -> {:ok, Enum.filter(names, &valid_digest?/1)}
      {:error, reason} -> {:error, "cache objects: #{:file.format_error(reason)}"}
    end
  end

  defp read_bounded_regular(path, label, maximum) do
    with {:ok, %{type: :regular, size: size}} <- File.lstat(path),
         true <- size <= maximum or {:error, "#{label} exceeds #{maximum} bytes"},
         {:ok, bytes} <- File.read(path),
         true <- byte_size(bytes) <= maximum or {:error, "#{label} exceeds #{maximum} bytes"} do
      {:ok, bytes}
    else
      {:ok, %{type: type}} -> {:error, "#{label} is #{type}, expected regular file"}
      {:error, reason} when is_atom(reason) -> {:error, "#{label}: #{:file.format_error(reason)}"}
      {:error, _} = error -> error
      false -> {:error, "#{label} changed while it was read"}
    end
  end

  defp decode(bytes) do
    case JSON.decode(bytes) do
      {:ok, map} -> {:ok, map}
      {:error, error} -> {:error, "invalid cache metadata JSON: #{Exception.message(error)}"}
    end
  rescue
    error -> {:error, "invalid cache metadata JSON: #{Exception.message(error)}"}
  end

  defp validate_identity(identity) do
    if valid_digest?(identity),
      do: :ok,
      else: {:error, "cache identity must be a full lowercase SHA-256"}
  end

  defp valid_digest?(value), do: is_binary(value) and Regex.match?(@digest, value)

  defp validate_keep(keep) do
    invalid = Enum.reject(keep, &valid_digest?/1)

    if invalid == [],
      do: :ok,
      else: {:error, "cache keep identities must be full lowercase SHA-256 values"}
  end

  defp positive(value, _, maximum) when is_integer(value) and value > 0 and value <= maximum,
    do: :ok

  defp positive(_, name, maximum),
    do: {:error, "#{name} must be an integer from 1 through #{maximum}"}

  defp objects_path(cache_root), do: Path.join(cache_root, "objects")

  defp entry_path(cache_root, build_identity),
    do: Path.join(objects_path(cache_root), build_identity)

  defp wrap_one(:ok), do: :ok
  defp wrap_one({:error, error}), do: {:error, [error]}
  defp wrap({:ok, value}), do: {:ok, value}
  defp wrap({:error, error}), do: {:error, [error]}
end
