defmodule Wotex.Conformance.Corpus do
  @moduledoc """
  A verified, content-addressed collection of conformance vectors.

  The manifest fixes every vector file and digest. Symbolic links, path
  traversal, duplicate vector IDs, undeclared files, and digest mismatches are
  rejected before any target is invoked.

  `load/1` bounds the manifest, individual vector files, and total vector count;
  verifies the declared directory contents; constructs every
  `Wotex.Conformance.Vector`; and checks the aggregate canonical digest. A
  corpus may also be constructed from already decoded values with `from_map/1`.
  Vectors are sorted by identifier before the corpus digest is computed.

  Verification establishes content identity and local structural validity. It
  does not establish that a target supports the claims or that each cited
  standard interpretation is correct. Those questions require runner results
  and provenance review. The filesystem is read only during an explicit
  `load/1` call; loading the library performs no I/O.
  """

  alias Wotex.Conformance.{Canonical, Error, Input, Value, Vector}

  @schema_version "1.0"
  @manifest "manifest.json"
  @max_manifest_bytes 1_048_576
  @max_vector_bytes 4_194_304
  @max_vectors 10_000

  @enforce_keys [:schema_version, :id, :revision, :vectors, :digest]
  defstruct [:schema_version, :id, :revision, :vectors, :digest]

  @type t :: %__MODULE__{
          schema_version: String.t(),
          id: String.t(),
          revision: String.t(),
          vectors: [Vector.t()],
          digest: String.t()
        }

  @doc """
  Loads and verifies a corpus directory from its `manifest.json`.

  Every declared vector is checked before the corpus is returned. Undeclared
  files, symbolic links, traversal, duplicate IDs, and digest mismatches fail
  closed.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, Error.t()}
  def load(directory) when is_binary(directory) and directory != "" do
    manifest_path = Path.join(directory, @manifest)

    with {:ok, manifest} <- read_json_file(manifest_path, @max_manifest_bytes),
         :ok <- Input.only_keys(manifest, ~w(schema_version id revision vectors digest)),
         :ok <- validate_schema_version(manifest),
         {:ok, id_input} <- Input.required(manifest, :id),
         {:ok, id} <- Value.validate_identifier(id_input, "id"),
         {:ok, revision_input} <- Input.required(manifest, :revision),
         {:ok, revision} <- Value.validate_identifier(revision_input, "revision", max_bytes: 64),
         {:ok, entries} <- validate_entries(Input.optional(manifest, :vectors, nil)),
         :ok <- validate_directory_entries(directory, entries),
         {:ok, vectors} <- load_vectors(directory, entries),
         {:ok, corpus} <- build(id, revision, vectors),
         :ok <- validate_manifest_digest(manifest, corpus.digest) do
      {:ok, corpus}
    end
  end

  def load(_directory),
    do: {:error, Error.new(:invalid_corpus_path, :corpus, "corpus path must be a non-empty string")}

  @doc "Constructs a content-addressed corpus from already decoded data."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(input) when is_map(input) do
    with :ok <- Input.only_keys(input, ~w(schema_version id revision vectors digest)),
         {:ok, id_input} <- Input.required(input, :id),
         {:ok, id} <- Value.validate_identifier(id_input, "id"),
         {:ok, revision_input} <- Input.required(input, :revision),
         {:ok, revision} <- Value.validate_identifier(revision_input, "revision", max_bytes: 64),
         {:ok, vector_inputs} <- Input.required(input, :vectors),
         {:ok, vectors} <- construct_vectors(vector_inputs) do
      build(id, revision, vectors)
    end
  end

  def from_map(_input), do: {:error, Error.new(:invalid_type, :corpus, "corpus must be an object")}

  @doc "Alias for `from_map/1`, the map-shaped corpus constructor."
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(input), do: from_map(input)

  @doc "Serializes a corpus, optionally omitting its digest with `include_digest: false`."
  @spec to_map(t(), keyword()) :: map()
  def to_map(%__MODULE__{} = corpus, options \\ []) do
    map = %{
      "schema_version" => corpus.schema_version,
      "id" => corpus.id,
      "revision" => corpus.revision,
      "vectors" => Enum.map(corpus.vectors, &Vector.to_map/1)
    }

    if Keyword.get(options, :include_digest, true) do
      Map.put(map, "digest", corpus.digest)
    else
      map
    end
  end

  defp build(id, revision, vectors) do
    sorted = Enum.sort_by(vectors, & &1.id)

    cond do
      sorted == [] ->
        {:error, Error.new(:empty_corpus, :corpus, "corpus must contain at least one vector")}

      length(sorted) > @max_vectors ->
        {:error,
         Error.new(:limit_exceeded, :limits, "corpus exceeds its vector limit",
           details: %{"max_vectors" => @max_vectors}
         )}

      duplicate_ids?(sorted) ->
        {:error, Error.new(:duplicate_vector, :corpus, "corpus contains duplicate vector IDs")}

      true ->
        corpus = %__MODULE__{
          schema_version: @schema_version,
          id: id,
          revision: revision,
          vectors: sorted,
          digest: ""
        }

        with {:ok, digest} <- Canonical.digest(to_map(corpus, include_digest: false)) do
          {:ok, %{corpus | digest: digest}}
        end
    end
  end

  defp construct_vectors(values) when is_list(values) and length(values) <= @max_vectors do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, vectors} ->
      case value do
        %Vector{} = vector ->
          {:cont, {:ok, [vector | vectors]}}

        input when is_map(input) ->
          case Vector.from_map(input) do
            {:ok, vector} -> {:cont, {:ok, [vector | vectors]}}
            {:error, error} -> {:halt, {:error, error}}
          end

        _value ->
          {:halt, {:error, Error.new(:invalid_type, :corpus, "corpus vectors must be objects")}}
      end
    end)
    |> then(fn
      {:ok, vectors} -> {:ok, Enum.reverse(vectors)}
      {:error, error} -> {:error, error}
    end)
  end

  defp construct_vectors(_values),
    do: {:error, Error.new(:invalid_value, :corpus, "vectors must be a bounded list")}

  defp validate_schema_version(%{"schema_version" => @schema_version}), do: :ok

  defp validate_schema_version(_manifest) do
    {:error,
     Error.new(:unsupported_schema_version, :corpus, "corpus schema_version is not supported")}
  end

  defp validate_entries(entries)
       when is_list(entries) and entries != [] and length(entries) <= @max_vectors do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, valid} ->
      case validate_entry(entry) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | valid]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> then(fn
      {:ok, valid} ->
        valid = Enum.reverse(valid)

        if duplicate_entry_files?(valid) do
          {:error,
           Error.new(
             :duplicate_vector_file,
             :corpus,
             "corpus manifest contains duplicate vector files"
           )}
        else
          {:ok, valid}
        end

      {:error, error} ->
        {:error, error}
    end)
  end

  defp validate_entries(_entries),
    do:
      {:error,
       Error.new(:invalid_manifest, :corpus, "manifest vectors must be a non-empty bounded list")}

  defp validate_entry(entry) when is_map(entry) do
    with :ok <- Input.only_keys(entry, ~w(id file digest)),
         {:ok, id_input} <- Input.required(entry, :id),
         {:ok, id} <- Value.validate_identifier(id_input, "id"),
         {:ok, file} <- Input.required(entry, :file),
         :ok <- validate_filename(file),
         {:ok, digest} <- Input.required(entry, :digest),
         :ok <- validate_digest(digest) do
      {:ok, %{"id" => id, "file" => file, "digest" => digest}}
    end
  end

  defp validate_entry(_entry),
    do: {:error, Error.new(:invalid_manifest_entry, :corpus, "vector manifest entry is invalid")}

  defp validate_filename(file) when is_binary(file) do
    if Path.basename(file) == file and String.match?(file, ~r/^[a-z0-9][a-z0-9._-]*\.json$/) do
      :ok
    else
      {:error,
       Error.new(:invalid_vector_filename, :corpus, "vector filename must be a local JSON basename")}
    end
  end

  defp validate_filename(_file),
    do: {:error, Error.new(:invalid_vector_filename, :corpus, "vector filename must be a string")}

  defp validate_digest(digest) do
    if Canonical.valid_digest?(digest),
      do: :ok,
      else: {:error, Error.new(:invalid_digest, :corpus, "vector digest must be lowercase SHA-256")}
  end

  defp validate_directory_entries(directory, entries) do
    expected =
      entries
      |> Enum.map(& &1["file"])
      |> then(&MapSet.new([@manifest | &1]))

    case File.ls(directory) do
      {:ok, filenames} ->
        undeclared = filenames |> MapSet.new() |> MapSet.difference(expected)

        if MapSet.size(undeclared) == 0 do
          :ok
        else
          {:error,
           Error.new(:undeclared_corpus_file, :corpus, "corpus contains undeclared files",
             details: %{"count" => MapSet.size(undeclared)}
           )}
        end

      {:error, _reason} ->
        {:error, Error.new(:corpus_unreadable, :corpus, "corpus directory could not be read")}
    end
  end

  defp load_vectors(directory, entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, vectors} ->
      path = Path.join(directory, entry["file"])

      with {:ok, input} <- read_json_file(path, @max_vector_bytes),
           {:ok, vector} <- Vector.from_map(input),
           :ok <- compare_entry(entry, input, vector) do
        {:cont, {:ok, [vector | vectors]}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> then(fn
      {:ok, vectors} -> {:ok, Enum.reverse(vectors)}
      {:error, error} -> {:error, error}
    end)
  end

  defp compare_entry(entry, input, vector) do
    cond do
      entry["id"] != vector.id ->
        {:error,
         Error.new(
           :vector_identity_mismatch,
           :corpus,
           "vector ID does not match its manifest entry"
         )}

      entry["digest"] != vector.digest ->
        {:error,
         Error.new(
           :vector_digest_mismatch,
           :corpus,
           "vector digest does not match its manifest entry"
         )}

      Map.get(input, "digest") != vector.digest ->
        {:error,
         Error.new(
           :vector_digest_mismatch,
           :corpus,
           "vector embedded digest does not match its content"
         )}

      true ->
        :ok
    end
  end

  defp validate_manifest_digest(manifest, actual_digest) do
    case Map.get(manifest, "digest") do
      ^actual_digest ->
        :ok

      _digest ->
        {:error,
         Error.new(:corpus_digest_mismatch, :corpus, "corpus digest does not match its manifest")}
    end
  end

  defp read_json_file(path, max_bytes) do
    with {:ok, %File.Stat{type: :regular, size: size}} when size <= max_bytes <- File.lstat(path),
         {:ok, bytes} <- File.read(path),
         {:ok, decoded} <- Jason.decode(bytes) do
      {:ok, decoded}
    else
      {:ok, %File.Stat{type: :regular}} ->
        {:error, Error.new(:limit_exceeded, :limits, "corpus file exceeds its byte limit")}

      {:ok, _stat} ->
        {:error, Error.new(:invalid_corpus_file, :corpus, "corpus entry must be a regular file")}

      {:error, %Jason.DecodeError{}} ->
        {:error, Error.new(:invalid_json, :corpus, "corpus file contains invalid JSON")}

      {:error, _reason} ->
        {:error, Error.new(:corpus_unreadable, :corpus, "corpus file could not be read")}
    end
  end

  defp duplicate_ids?(vectors) do
    ids = Enum.map(vectors, & &1.id)
    length(ids) != MapSet.size(MapSet.new(ids))
  end

  defp duplicate_entry_files?(entries) do
    files = Enum.map(entries, & &1["file"])
    length(files) != MapSet.size(MapSet.new(files))
  end
end
