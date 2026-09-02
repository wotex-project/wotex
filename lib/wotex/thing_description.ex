defmodule Wotex.ThingDescription do
  @moduledoc """
  Immutable W3C WoT Thing Description 1.1 value.

  Use the public functions instead of depending on struct fields. Unknown
  extension members are preserved at JSON-value semantics.
  """

  alias Wotex.{Error, JSON}
  alias Wotex.ThingDescription.Validator

  @default_max_bytes 1_048_576

  @opaque t :: %__MODULE__{
            document: JSON.json_value(),
            source: binary() | nil,
            changed?: boolean()
          }

  @enforce_keys [:document]
  defstruct [:document, :source, changed?: false]

  @doc "Parses and validates `application/td+json` bytes."
  @spec parse(binary(), keyword()) :: {:ok, t()} | {:error, Error.t() | [Error.t()]}
  def parse(json, opts \\ [])

  def parse(json, opts) when is_binary(json) do
    max_bytes = positive_limit(opts, :max_bytes, @default_max_bytes)

    with :ok <- check_byte_limit(json, max_bytes),
         {:ok, decoded} <- decode(json),
         {:ok, td} <- from_map(decoded, Keyword.put(opts, :source, json)) do
      {:ok, td}
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

  @doc "Builds a Thing Description from a JSON-compatible map."
  @spec from_map(map(), keyword()) :: {:ok, t()} | {:error, Error.t() | [Error.t()]}
  def from_map(document, opts \\ [])

  def from_map(document, opts) when is_map(document) do
    source = Keyword.get(opts, :source)
    validate? = Keyword.get(opts, :validate, true)

    with :ok <- JSON.validate(document, opts),
         %__MODULE__{} = td <- %__MODULE__{document: document, source: source, changed?: false},
         {:ok, validated} <- maybe_validate(td, validate?, opts) do
      {:ok, validated}
    end
  end

  def from_map(_document, _opts) do
    {:error, Error.new(:object_required, :value, "A Thing Description must be a JSON object", "/")}
  end

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

  @doc "Encodes a Thing Description as source, compact, pretty, or canonical TD JSON."
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
  @spec schema_info() :: map()
  def schema_info, do: Validator.schema_info()

  defp check_byte_limit(json, max_bytes) when byte_size(json) <= max_bytes, do: :ok

  defp check_byte_limit(json, max_bytes) do
    {:error,
     Error.new(:byte_limit_exceeded, :parse, "TD JSON exceeds the configured byte limit", "/", %{
       bytes: byte_size(json),
       max_bytes: max_bytes
     })}
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        {:error,
         Error.new(:invalid_json, :parse, "Thing Description JSON could not be decoded", "/", %{
           reason: Exception.message(reason)
         })}
    end
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

  defp positive_limit(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> default
    end
  end
end
