defmodule Wotex.Directory.Page do
  @moduledoc """
  One revision-bound page of Thing Description Directory entries.
  """

  alias Wotex.Directory.{Entry, Error, Query}

  @enforce_keys [:entries, :offset, :limit, :collection_revision]
  defstruct [:entries, :offset, :limit, :next_offset, :collection_revision]

  @type t :: %__MODULE__{
          entries: [Entry.t()],
          offset: non_neg_integer(),
          limit: pos_integer(),
          next_offset: non_neg_integer() | nil,
          collection_revision: String.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  @doc "Builds a page value and validates its structural fields."
  def new(options) when is_list(options) do
    if valid_options?(options) do
      page = %__MODULE__{
        entries: Keyword.get(options, :entries),
        offset: Keyword.get(options, :offset),
        limit: Keyword.get(options, :limit),
        next_offset: Keyword.get(options, :next_offset),
        collection_revision: Keyword.get(options, :collection_revision)
      }

      if base_valid?(page), do: {:ok, page}, else: invalid()
    else
      invalid()
    end
  end

  def new(_options), do: invalid()

  @spec new!(keyword()) :: t()
  @doc "Builds a page value or raises the returned typed error."
  def new!(options) do
    case new(options) do
      {:ok, page} -> page
      {:error, error} -> raise error
    end
  end

  @spec validate(t(), Query.t(), DateTime.t()) :: :ok | {:error, Error.t()}
  @doc "Validates a repository page against its query and activity time."
  def validate(%__MODULE__{} = page, %Query{} = query, %DateTime{} = active_at) do
    if base_valid?(page) do
      validate_contents(page, query, active_at)
    else
      invalid()
    end
  end

  def validate(_page, _query, _active_at), do: invalid()

  @spec next_query(t(), Query.t()) :: Query.t() | nil
  @doc "Builds the revision-bound next query, or returns nil for a terminal page."
  def next_query(%__MODULE__{next_offset: nil}, %Query{}), do: nil

  def next_query(%__MODULE__{} = page, %Query{} = query) do
    %Query{
      query
      | offset: page.next_offset,
        collection_revision: page.collection_revision
    }
  end

  @spec mark_retrieved(t(), DateTime.t()) :: t()
  @doc "Assigns one shared response-only retrieval time to every page entry."
  def mark_retrieved(%__MODULE__{} = page, %DateTime{} = now) do
    %{page | entries: Enum.map(page.entries, &Entry.mark_retrieved(&1, now))}
  end

  defp base_valid?(%__MODULE__{} = page) do
    is_list(page.entries) and Enum.all?(page.entries, &Entry.valid?/1) and
      is_integer(page.offset) and page.offset >= 0 and is_integer(page.limit) and
      page.limit > 0 and is_binary(page.collection_revision) and
      page.collection_revision != "" and
      (is_nil(page.next_offset) or
         (is_integer(page.next_offset) and page.next_offset >= 0))
  end

  defp valid_options?(options) do
    allowed = [:entries, :offset, :limit, :next_offset, :collection_revision]
    Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in allowed))
  end

  defp valid_next_offset?(%__MODULE__{next_offset: nil}), do: true

  defp valid_next_offset?(%__MODULE__{} = page) do
    page.entries != [] and page.next_offset == page.offset + length(page.entries)
  end

  defp validate_contents(page, query, active_at) do
    identifiers = Enum.map(page.entries, & &1.identifier)

    cond do
      page.offset != query.offset or page.limit != query.limit ->
        invalid()

      length(page.entries) > query.limit ->
        invalid()

      query.collection_revision != nil and
          page.collection_revision != query.collection_revision ->
        {:error, Error.new(:collection_changed, :listing, :list)}

      identifiers != Enum.sort(identifiers) or
          length(identifiers) != length(Enum.uniq(identifiers)) ->
        invalid()

      not Enum.all?(page.entries, &Entry.active?(&1, active_at)) ->
        invalid()

      not valid_next_offset?(page) ->
        invalid()

      true ->
        :ok
    end
  end

  defp invalid, do: {:error, Error.new(:invalid_page, :listing, :list)}
end
