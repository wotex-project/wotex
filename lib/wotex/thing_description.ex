defmodule Wotex.ThingDescription do
  @moduledoc """
  An immutable W3C WoT Thing Description 1.1 value.

  A Thing Description is the standardized metadata document for a Thing, not a
  database row, transport connection, device process, or digital-twin state
  holder. Wotex validates its TD 1.1 structure, context/title semantics, and
  security-definition references while preserving unknown extension members at
  native JSON-value semantics.

  Parse `application/td+json` with `parse/2`, or use `from_map/2` after a
  consumer has decoded JSON elsewhere. Parsing retains the exact source bytes
  until a value is changed. `encode/2` offers source, compact, pretty, and
  deterministic canonical modes.

  Byte, depth, node, string, and collection limits are applied before or
  during construction; for a native map, `:max_bytes` bounds the total string
  payload. All
  expected input failures return `Wotex.Error` values (or a list of validation
  errors); `parse!/2` is the opt-in raising variant.

  Use the public functions instead of depending on struct fields. The
  representation may evolve in compatible releases.
  """

  alias Wotex.{Error, JSON}
  alias Wotex.ThingDescription.Validator

  @typedoc "Pinned identity and provenance of the bundled informative TD 1.1 schema."
  @type schema_info :: %{
          standard: <<_::232>>,
          recommendation_date: <<_::80>>,
          schema_version: <<_::160>>,
          upstream_tag: <<_::48>>,
          upstream_commit: <<_::320>>,
          sha256: <<_::512>>,
          informative: true
        }

  @type t :: %__MODULE__{
          document: map(),
          source: binary() | nil,
          changed?: boolean()
        }

  @enforce_keys [:document]
  defstruct [:document, :source, changed?: false]

  @doc """
  Parses and validates `application/td+json` bytes.

  Limit options are `:max_bytes`, `:max_depth`, `:max_nodes`,
  `:max_string_bytes`, and `:max_collection_size`; see `Wotex.JSON.Limits` for
  defaults. Invalid limit values are rejected with `invalid_limit`. Duplicate
  object members are rejected during decoding.
  `validate: false` skips the TD schema and semantic pass but never skips
  JSON-value or resource-limit checks.
  """
  @spec parse(binary(), keyword()) :: {:ok, t()} | {:error, Error.t() | [Error.t()]}
  def parse(json, opts \\ [])

  def parse(json, opts) when is_binary(json) do
    validate? = Keyword.get(opts, :validate, true)

    with {:ok, decoded} <- JSON.decode(json, opts),
         {:ok, document} <- require_object(decoded) do
      maybe_validate(
        %__MODULE__{document: document, source: json, changed?: false},
        validate?,
        opts
      )
    end
  end

  def parse(_json, _opts) do
    {:error, Error.new(:invalid_input, :parse, "Thing Description input must be binary")}
  end

  @doc "Parses and validates TD JSON, raising `Wotex.Error` on failure."
  @spec parse!(binary(), keyword()) :: t()
  def parse!(json, opts \\ []) do
    case parse(json, opts) do
      {:ok, td} -> td
      {:error, [%Error{} = first | _rest]} -> raise first
      {:error, %Error{} = error} -> raise error
    end
  end

  @doc """
  Builds a Thing Description from a JSON-compatible map.

  The map is retained without lossy atomization or extension filtering. It is
  validated by default; pass `validate: false` only for staged ingestion where
  a later call to `validate/2` is guaranteed.
  """
  @spec from_map(map(), keyword()) :: {:ok, t()} | {:error, Error.t() | [Error.t()]}
  def from_map(document, opts \\ [])

  def from_map(document, opts) when is_map(document) do
    source = Keyword.get(opts, :source)
    validate? = Keyword.get(opts, :validate, true)

    with :ok <- JSON.validate(document, opts),
         %__MODULE__{} = td <- %__MODULE__{document: document, source: source, changed?: false} do
      maybe_validate(td, validate?, opts)
    end
  end

  def from_map(document, _opts), do: require_object(document)

  @doc "Returns the complete JSON-compatible Thing Description map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{document: document}), do: document

  @doc "Returns the optional Thing Description `id`."
  @spec id(t()) :: String.t() | nil
  def id(%__MODULE__{document: document}), do: Map.get(document, "id")

  @doc "Returns a validated value with `id` replaced."
  @spec put_id(t(), String.t(), keyword()) :: {:ok, t()} | {:error, Error.t() | [Error.t()]}
  def put_id(td, id, opts \\ [])

  def put_id(%__MODULE__{document: document}, id, opts)
      when is_binary(id) and byte_size(id) > 0 do
    document
    |> Map.put("id", id)
    |> from_map(Keyword.put(opts, :source, nil))
    |> mark_changed()
  end

  def put_id(%__MODULE__{}, _id, _opts) do
    {:error, Error.new(:invalid_id, :value, "Thing Description id must be non-empty", "/id")}
  end

  @doc "Validates a Thing Description against the pinned TD 1.1 baseline."
  @spec validate(t(), keyword()) :: {:ok, t()} | {:error, [Error.t()]}
  def validate(%__MODULE__{} = td, opts \\ []), do: Validator.validate(td, opts)

  @doc """
  Encodes a Thing Description as source, compact, pretty, or canonical TD JSON.

  Canonical output is deterministic within this package but is not an RFC 8785
  JSON Canonicalization Scheme claim.
  """
  @spec encode(t(), :source | :compact | :pretty | :canonical) ::
          {:ok, binary()} | {:error, Error.t()}
  def encode(%__MODULE__{source: source, changed?: false}, :source) when is_binary(source),
    do: {:ok, source}

  def encode(%__MODULE__{}, :source) do
    {:error,
     Error.new(
       :source_unavailable,
       :encode,
       "Original source bytes are unavailable after construction or mutation"
     )}
  end

  def encode(%__MODULE__{document: document}, :canonical), do: JSON.encode(document)

  def encode(%__MODULE__{document: document}, :compact) do
    encode_with_jason(document, [])
  end

  def encode(%__MODULE__{document: document}, :pretty) do
    encode_with_jason(document, pretty: true)
  end

  def encode(%__MODULE__{}, mode) do
    {:error,
     Error.new(:unsupported_encoding, :encode, "Unsupported Thing Description encoding", "/", %{
       mode: inspect(mode, limit: 10, printable_limit: 40)
     })}
  end

  @doc "Returns the immutable identity of the bundled informative TD 1.1 schema."
  @spec schema_info() :: schema_info()
  def schema_info, do: Validator.schema_info()

  defp require_object(document) when is_map(document), do: {:ok, document}

  defp require_object(_document) do
    {:error, Error.new(:object_required, :value, "A Thing Description must be a JSON object", "/")}
  end

  defp maybe_validate(td, true, opts), do: Validator.validate(td, opts)
  defp maybe_validate(td, false, _opts), do: {:ok, td}

  defp mark_changed({:ok, %__MODULE__{} = td}), do: {:ok, %{td | changed?: true, source: nil}}
  defp mark_changed({:error, error}), do: {:error, error}

  defp encode_with_jason(document, opts) do
    case Jason.encode(document, opts) do
      {:ok, json} ->
        {:ok, json}

      {:error, reason} ->
        {:error,
         Error.new(:encode_failed, :encode, "Thing Description JSON encoding failed", "/", %{
           reason: inspect(reason, limit: 20, printable_limit: 80)
         })}
    end
  end
end
