defmodule Wotex.ThingModel do
  @moduledoc """
  An immutable W3C WoT Thing Model 1.1 value.

  A Thing Model describes a reusable model or class of Things. Unlike a Thing
  Description, it can contain placeholders, optional Interaction Affordances,
  and `tm:ref` references, and it need not identify an operational Thing.

  Parse `application/tm+json` with `parse/2`, or use `from_map/2` after a
  consumer has decoded JSON. Unknown extension terms and Thing Model template
  values are preserved at native JSON-value semantics. Validation is local and
  uses a schema pinned to the W3C Thing Description 1.1 Recommendation; remote
  JSON-LD contexts are never fetched.

  Byte, depth, node, string, and collection limits are enforced before a value
  crosses the package boundary. Source bytes remain available until mutation, while canonical
  encoding is deterministic within Wotex and makes no RFC 8785 claim.
  """

  alias Wotex.{Error, JSON}
  alias Wotex.ThingModel.Validator

  @typedoc "Pinned identity and provenance of the bundled informative Thing Model schema."
  @type schema_info :: %{
          standard: String.t(),
          recommendation_date: String.t(),
          schema_version: String.t(),
          upstream_tag: String.t(),
          upstream_commit: String.t(),
          upstream_sha256: String.t(),
          bundled_sha256: String.t(),
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
  Parses and validates `application/tm+json` bytes.

  Limit options are `:max_bytes`, `:max_depth`, `:max_nodes`,
  `:max_string_bytes`, and `:max_collection_size`; see `Wotex.JSON.Limits` for
  defaults. Invalid limit values are rejected with `invalid_limit`. Duplicate
  object members are rejected during decoding.
  `validate: false` skips the Thing Model schema and semantic pass but retains
  JSON-value and resource-limit validation.
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

  def parse(_, _) do
    {:error, Error.new(:invalid_input, :parse, "Thing Model input must be binary")}
  end

  @doc "Parses and validates Thing Model JSON, raising `Wotex.Error` on failure."
  @spec parse!(binary(), keyword()) :: t()
  def parse!(json, opts \\ []) do
    case parse(json, opts) do
      {:ok, tm} -> tm
      {:error, [%Error{} = first | _]} -> raise first
      {:error, %Error{} = error} -> raise error
    end
  end

  @doc """
  Builds a Thing Model from a JSON-compatible map.

  The complete map is preserved without atomization or extension filtering.
  Validation is enabled by default.
  """
  @spec from_map(map(), keyword()) :: {:ok, t()} | {:error, Error.t() | [Error.t()]}
  def from_map(document, opts \\ [])

  def from_map(document, opts) when is_map(document) do
    source = Keyword.get(opts, :source)
    validate? = Keyword.get(opts, :validate, true)

    with :ok <- JSON.validate(document, opts),
         %__MODULE__{} = tm <- %__MODULE__{document: document, source: source, changed?: false} do
      maybe_validate(tm, validate?, opts)
    end
  end

  def from_map(document, _), do: require_object(document)

  @doc "Returns the complete JSON-compatible Thing Model map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{document: document}), do: document

  @doc "Returns the optional Thing Model `id`."
  @spec id(t()) :: String.t() | nil
  def id(%__MODULE__{document: document}), do: Map.get(document, "id")

  @doc "Returns a validated Thing Model with `id` replaced."
  @spec put_id(t(), String.t(), keyword()) :: {:ok, t()} | {:error, Error.t() | [Error.t()]}
  def put_id(tm, id, opts \\ [])

  def put_id(%__MODULE__{document: document}, id, opts)
      when is_binary(id) and byte_size(id) > 0 do
    document
    |> Map.put("id", id)
    |> from_map(Keyword.put(opts, :source, nil))
    |> mark_changed()
  end

  def put_id(%__MODULE__{}, _, _) do
    {:error, Error.new(:invalid_id, :value, "Thing Model id must be non-empty", "/id")}
  end

  @doc "Validates a Thing Model against the pinned W3C 1.1 baseline."
  @spec validate(t(), keyword()) :: {:ok, t()} | {:error, [Error.t()]}
  def validate(%__MODULE__{} = tm, opts \\ []), do: Validator.validate(tm, opts)

  @doc """
  Encodes a Thing Model as source, compact, pretty, or canonical JSON.

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
  def encode(%__MODULE__{document: document}, :compact), do: encode_with_jason(document, [])

  def encode(%__MODULE__{document: document}, :pretty) do
    encode_with_jason(document, pretty: true)
  end

  def encode(%__MODULE__{}, mode) do
    {:error,
     Error.new(:unsupported_encoding, :encode, "Unsupported Thing Model encoding", "/", %{
       mode: inspect(mode, limit: 10, printable_limit: 40)
     })}
  end

  @doc "Returns the immutable identity of the bundled informative Thing Model schema."
  @spec schema_info() :: schema_info()
  def schema_info, do: Validator.schema_info()

  defp require_object(document) when is_map(document), do: {:ok, document}

  defp require_object(_) do
    {:error, Error.new(:object_required, :value, "A Thing Model must be a JSON object", "/")}
  end

  defp maybe_validate(tm, true, opts), do: Validator.validate(tm, opts)
  defp maybe_validate(tm, false, _), do: {:ok, tm}

  defp mark_changed({:ok, %__MODULE__{} = tm}), do: {:ok, %{tm | changed?: true, source: nil}}
  defp mark_changed({:error, error}), do: {:error, error}

  defp encode_with_jason(document, opts) do
    case Jason.encode(document, opts) do
      {:ok, json} ->
        {:ok, json}

      {:error, reason} ->
        {:error,
         Error.new(:encode_failed, :encode, "Thing Model JSON encoding failed", "/", %{
           reason: inspect(reason, limit: 20, printable_limit: 80)
         })}
    end
  end
end
