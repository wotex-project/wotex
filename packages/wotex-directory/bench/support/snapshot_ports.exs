defmodule Wotex.Directory.Bench.SnapshotPorts do
  @moduledoc false

  # In-process consumer ports over an immutable snapshot. The repository
  # answers from a prebuilt map and sorted list and never stores anything, so a
  # benchmark measures the Directory mechanics (authorization order, Thing
  # Description validation, registration information, Merge Patch, page
  # validation) rather than a persistence system. Authorization always allows,
  # the clock is fixed and the identifier port returns one reserved URN.

  @behaviour Wotex.Directory.Authorization
  @behaviour Wotex.Directory.Clock
  @behaviour Wotex.Directory.Identifier
  @behaviour Wotex.Directory.Repository

  alias Wotex.Directory.{Cursor, Entry, Page, Query, Registration, Service}

  @now ~U[2026-01-01 00:00:00Z]
  @revision "revision-1"

  @type snapshot :: %{entries: %{String.t() => Entry.t()}, sorted: [Entry.t()]}

  @spec entry(Wotex.ThingDescription.t()) :: Entry.t()
  def entry(td) do
    {:ok, registration} = Registration.create(@now, :absent, :register)
    {:ok, entry} = Entry.new(Wotex.ThingDescription.id(td), td, registration)
    entry
  end

  @spec service([Entry.t()], Wotex.ThingDescription.t()) :: Service.t()
  def service(entries, introduction) do
    snapshot = %{
      entries: Map.new(entries, &{&1.identifier, &1}),
      sorted: Enum.sort_by(entries, & &1.identifier)
    }

    {:ok, service} =
      Service.new(
        repository: {__MODULE__, snapshot},
        authorization: {__MODULE__, nil},
        clock: {__MODULE__, nil},
        identifier: {__MODULE__, nil},
        introduction: introduction
      )

    service
  end

  @impl Wotex.Directory.Authorization
  @spec authorize(term(), term(), atom(), term(), term()) :: :ok
  def authorize(_, _, _, _, _), do: :ok

  @impl Wotex.Directory.Clock
  @spec now(term()) :: {:ok, DateTime.t()}
  def now(_), do: {:ok, @now}

  @impl Wotex.Directory.Identifier
  @spec generate(term()) :: {:ok, String.t()}
  def generate(_), do: {:ok, "urn:example:thing:anonymous"}

  @impl Wotex.Directory.Repository
  @spec fetch(snapshot(), String.t(), term()) :: {:ok, Entry.t()} | :not_found
  def fetch(snapshot, identifier, _) do
    case Map.fetch(snapshot.entries, identifier) do
      {:ok, entry} -> {:ok, entry}
      :error -> :not_found
    end
  end

  @impl Wotex.Directory.Repository
  @spec insert(snapshot(), Entry.t(), term()) :: {:ok, Entry.t()} | {:error, :already_exists}
  def insert(snapshot, entry, _) do
    if Map.has_key?(snapshot.entries, entry.identifier),
      do: {:error, :already_exists},
      else: {:ok, entry}
  end

  @impl Wotex.Directory.Repository
  @spec replace(snapshot(), Entry.t(), pos_integer(), term()) ::
          {:ok, Entry.t()} | {:error, :conflict | :not_found}
  def replace(snapshot, entry, expected_version, _) do
    case Map.fetch(snapshot.entries, entry.identifier) do
      {:ok, %Entry{version: ^expected_version}} -> {:ok, entry}
      {:ok, _} -> {:error, :conflict}
      :error -> {:error, :not_found}
    end
  end

  @impl Wotex.Directory.Repository
  @spec delete(snapshot(), String.t(), pos_integer(), term()) :: :ok | {:error, :conflict}
  def delete(snapshot, identifier, expected_version, _) do
    case Map.fetch(snapshot.entries, identifier) do
      {:ok, %Entry{version: ^expected_version}} -> :ok
      _ -> {:error, :conflict}
    end
  end

  @impl Wotex.Directory.Repository
  @spec list(snapshot(), Query.t(), Cursor.t() | nil, DateTime.t(), term()) ::
          {:ok, Page.t()} | {:error, Wotex.Directory.Error.t()}
  def list(snapshot, %Query{limit: limit}, cursor, active_at, _) do
    candidates =
      snapshot.sorted
      |> after_cursor(cursor)
      |> Stream.filter(&Entry.active?(&1, active_at))
      |> Enum.take(limit + 1)

    Page.new(
      entries: Enum.take(candidates, limit),
      collection_revision: @revision,
      more?: length(candidates) > limit
    )
  end

  @impl Wotex.Directory.Repository
  @spec expire_due(snapshot(), DateTime.t(), pos_integer(), atom(), term()) :: {:ok, []}
  def expire_due(_, _, _, _, _), do: {:ok, []}

  defp after_cursor(entries, nil), do: entries

  defp after_cursor(entries, %Cursor{last_identifier: last}),
    do: Enum.drop_while(entries, &(&1.identifier <= last))
end
