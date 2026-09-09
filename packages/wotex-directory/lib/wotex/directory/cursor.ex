defmodule Wotex.Directory.Cursor do
  @moduledoc """
  Opaque keyset continuation value for bounded Discovery listing.

  A cursor binds the collection revision that issued it to the last identifier
  of the page it continues. The package owns the encoding: a transport host and
  a client treat the string as opaque and return it unchanged, while a
  repository adapter receives the decoded value and selects the entries whose
  identifier is greater than `last_identifier` in ascending Unicode code point
  order.

  Keyset continuation never depends on an offset into a time-dependent view, so
  an entry that reaches absolute expiry between pages is omitted from the
  following page.

  ## Examples

      iex> {:ok, encoded} = Wotex.Directory.Cursor.encode("revision-1", "urn:example:thing:1")
      iex> {:ok, cursor} = Wotex.Directory.Cursor.decode(encoded)
      iex> {cursor.collection_revision, cursor.last_identifier}
      {"revision-1", "urn:example:thing:1"}

  """

  alias Wotex.Directory.{Error, Identifier}

  @prefix "wtd1"

  @enforce_keys [:collection_revision, :last_identifier]
  defstruct [:collection_revision, :last_identifier]

  @type t :: %__MODULE__{collection_revision: String.t(), last_identifier: String.t()}

  @doc """
  Encodes the continuation of a page as an opaque cursor string.

  The revision is the repository-defined collection revision that produced the
  page and the identifier is the last entry identifier on that page.
  """
  @spec encode(String.t(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def encode(collection_revision, last_identifier) do
    if valid_revision?(collection_revision) and Identifier.valid?(last_identifier) do
      {:ok, Enum.join([@prefix, segment(collection_revision), segment(last_identifier)], ".")}
    else
      invalid()
    end
  end

  @doc "Decodes an opaque cursor into its revision binding and last identifier."
  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(cursor) when is_binary(cursor) do
    with [@prefix, revision_segment, identifier_segment] <- String.split(cursor, "."),
         {:ok, collection_revision} <- Base.url_decode64(revision_segment, padding: false),
         {:ok, last_identifier} <- Base.url_decode64(identifier_segment, padding: false),
         true <- valid_revision?(collection_revision) and Identifier.valid?(last_identifier) do
      {:ok,
       %__MODULE__{
         collection_revision: collection_revision,
         last_identifier: last_identifier
       }}
    else
      _ -> invalid()
    end
  end

  def decode(_), do: invalid()

  @doc "Reports whether a term is a decodable opaque cursor."
  @spec valid?(term()) :: boolean()
  def valid?(cursor), do: match?({:ok, _decoded}, decode(cursor))

  defp segment(value), do: Base.url_encode64(value, padding: false)

  defp valid_revision?(revision) do
    is_binary(revision) and revision != "" and String.valid?(revision)
  end

  defp invalid, do: {:error, Error.new(:invalid_request, :listing, :list)}
end
