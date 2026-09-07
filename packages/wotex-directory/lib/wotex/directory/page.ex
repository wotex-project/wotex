defmodule Wotex.Directory.Page do
  @moduledoc """
  One revision-bound page of Thing Description Directory entries.

  A page carries its ordered entries, the repository-defined collection
  revision that produced it, and an opaque `next_cursor` when the repository
  reported further entries. A repository builds the value with `new/1` and
  reports continuation with `more?: true`; the package derives the cursor from
  the collection revision and the last listed identifier.
  """

  alias Wotex.Directory.{Cursor, Entry, Error, Query}

  @enforce_keys [:entries, :collection_revision]
  defstruct [:entries, :next_cursor, :collection_revision]

  @type t :: %__MODULE__{
          entries: [Entry.t()],
          next_cursor: String.t() | nil,
          collection_revision: String.t()
        }

  @doc """
  Builds a page value and validates its structural fields.

  Options are `:entries`, `:collection_revision`, and `:more?`. A page that
  reports more entries must not be empty.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    if valid_options?(options) do
      build(
        Keyword.get(options, :entries),
        Keyword.get(options, :collection_revision),
        Keyword.get(options, :more?, false)
      )
    else
      invalid()
    end
  end

  def new(_options), do: invalid()

  @doc "Builds a page value or raises the returned typed error."
  @spec new!(keyword()) :: t()
  def new!(options) do
    case new(options) do
      {:ok, page} -> page
      {:error, error} -> raise error
    end
  end

  @doc "Validates a repository page against its query and activity time."
  @spec validate(t(), Query.t(), DateTime.t()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = page, %Query{} = query, %DateTime{} = active_at) do
    if base_valid?(page) do
      validate_contents(page, query, active_at)
    else
      invalid()
    end
  end

  def validate(_page, _query, _active_at), do: invalid()

  @doc "Builds the cursor-bound next query, or returns nil for a terminal page."
  @spec next_query(t(), Query.t()) :: Query.t() | nil
  def next_query(%__MODULE__{next_cursor: nil}, %Query{}), do: nil

  def next_query(%__MODULE__{} = page, %Query{} = query) do
    %Query{query | cursor: page.next_cursor}
  end

  @doc "Assigns one shared response-only retrieval time to every page entry."
  @spec mark_retrieved(t(), DateTime.t()) :: t()
  def mark_retrieved(%__MODULE__{} = page, %DateTime{} = now) do
    %{page | entries: Enum.map(page.entries, &Entry.mark_retrieved(&1, now))}
  end

  defp build(entries, collection_revision, more?) do
    page = %__MODULE__{entries: entries, collection_revision: collection_revision}

    with true <- base_valid?(page) and is_boolean(more?),
         {:ok, next_cursor} <- next_cursor(page, more?) do
      {:ok, %{page | next_cursor: next_cursor}}
    else
      _invalid -> invalid()
    end
  end

  defp next_cursor(_page, false), do: {:ok, nil}
  defp next_cursor(%__MODULE__{entries: []}, true), do: :error

  defp next_cursor(%__MODULE__{} = page, true) do
    last = List.last(page.entries)

    case Cursor.encode(page.collection_revision, last.identifier) do
      {:ok, cursor} -> {:ok, cursor}
      {:error, _error} -> :error
    end
  end

  defp base_valid?(%__MODULE__{} = page) do
    is_list(page.entries) and Enum.all?(page.entries, &Entry.valid?/1) and
      is_binary(page.collection_revision) and page.collection_revision != "" and
      (is_nil(page.next_cursor) or Cursor.valid?(page.next_cursor))
  end

  defp valid_options?(options) do
    allowed = [:entries, :collection_revision, :more?]
    Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed))
  end

  defp validate_contents(page, query, active_at) do
    with :ok <- validate_entries(page, query, active_at),
         :ok <- validate_continuation(page, query) do
      validate_next_cursor(page)
    end
  end

  defp validate_entries(page, query, active_at) do
    identifiers = Enum.map(page.entries, & &1.identifier)

    valid? =
      length(page.entries) <= query.limit and identifiers == Enum.sort(identifiers) and
        length(identifiers) == length(Enum.uniq(identifiers)) and
        Enum.all?(page.entries, &Entry.active?(&1, active_at))

    if valid?, do: :ok, else: invalid()
  end

  defp validate_continuation(%__MODULE__{}, %Query{cursor: nil}), do: :ok

  defp validate_continuation(page, %Query{cursor: cursor}) do
    case Cursor.decode(cursor) do
      {:ok, %Cursor{collection_revision: revision}}
      when revision != page.collection_revision ->
        {:error, Error.new(:collection_changed, :listing, :list)}

      {:ok, %Cursor{last_identifier: last}} ->
        if Enum.all?(page.entries, &(&1.identifier > last)), do: :ok, else: invalid()

      {:error, _error} ->
        invalid()
    end
  end

  defp validate_next_cursor(%__MODULE__{next_cursor: nil}), do: :ok
  defp validate_next_cursor(%__MODULE__{entries: []}), do: invalid()

  defp validate_next_cursor(%__MODULE__{} = page) do
    last = List.last(page.entries)

    if Cursor.encode(page.collection_revision, last.identifier) == {:ok, page.next_cursor} do
      :ok
    else
      invalid()
    end
  end

  defp invalid, do: {:error, Error.new(:invalid_page, :listing, :list)}
end
