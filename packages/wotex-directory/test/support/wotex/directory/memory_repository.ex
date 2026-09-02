defmodule Wotex.Directory.MemoryRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  alias Wotex.Directory.{Entry, Page, Query, Registration}

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(options \\ []) do
    entries =
      options |> Keyword.get(:entries, []) |> Map.new(&{&1.identifier, Entry.for_storage(&1)})

    revision = Keyword.get(options, :revision, 0)
    Agent.start_link(fn -> %{entries: entries, revision: revision, calls: []} end)
  end

  @spec snapshot(pid()) :: map()
  def snapshot(agent), do: Agent.get(agent, & &1)

  @spec entries(pid()) :: map()
  def entries(agent), do: agent |> snapshot() |> Map.fetch!(:entries)

  @spec calls(pid()) :: list()
  def calls(agent), do: agent |> snapshot() |> Map.fetch!(:calls) |> Enum.reverse()

  @impl true
  def fetch(agent, identifier, context) do
    Agent.get_and_update(agent, fn state ->
      result =
        case Map.fetch(state.entries, identifier) do
          {:ok, entry} -> {:ok, entry}
          :error -> :not_found
        end

      {result, record(state, {:fetch, identifier, context})}
    end)
  end

  @impl true
  def insert(agent, entry, context) do
    Agent.get_and_update(agent, fn state ->
      if Map.has_key?(state.entries, entry.identifier) do
        {{:error, :already_exists}, record(state, {:insert, entry.identifier, context})}
      else
        updated =
          state
          |> put_entry(entry)
          |> advance_revision()
          |> record({:insert, entry.identifier, context})

        {{:ok, entry}, updated}
      end
    end)
  end

  @impl true
  def replace(agent, entry, expected_version, context) do
    Agent.get_and_update(agent, fn state ->
      case Map.fetch(state.entries, entry.identifier) do
        :error ->
          {{:error, :not_found},
           record(state, {:replace, entry.identifier, expected_version, context})}

        {:ok, %{version: version}} when version != expected_version ->
          {{:error, :conflict},
           record(state, {:replace, entry.identifier, expected_version, context})}

        {:ok, _existing} ->
          updated =
            state
            |> put_entry(entry)
            |> advance_revision()
            |> record({:replace, entry.identifier, expected_version, context})

          {{:ok, entry}, updated}
      end
    end)
  end

  @impl true
  def delete(agent, identifier, expected_version, context) do
    Agent.get_and_update(agent, fn state ->
      case Map.fetch(state.entries, identifier) do
        :error ->
          {{:error, :not_found}, record(state, {:delete, identifier, expected_version, context})}

        {:ok, %{version: version}} when version != expected_version ->
          {{:error, :conflict}, record(state, {:delete, identifier, expected_version, context})}

        {:ok, _entry} ->
          updated =
            state
            |> Map.update!(:entries, &Map.delete(&1, identifier))
            |> advance_revision()
            |> record({:delete, identifier, expected_version, context})

          {:ok, updated}
      end
    end)
  end

  @impl true
  def list(agent, %Query{} = query, active_at, context) do
    Agent.get_and_update(agent, fn state ->
      result =
        case listing_revision(state, query.collection_revision, active_at) do
          {:ok, revision} -> page(state, query, active_at, revision)
          :collection_changed -> {:error, :collection_changed}
        end

      {result, record(state, {:list, query, active_at, context})}
    end)
  end

  @impl true
  def expire_due(agent, cutoff, limit, strategy, context) do
    Agent.get_and_update(agent, fn state ->
      due =
        state.entries
        |> Map.values()
        |> Enum.filter(&due?(&1, cutoff, strategy))
        |> Enum.sort_by(& &1.identifier)
        |> Enum.take(limit)

      {result_entries, updated_entries} = expire_entries(state.entries, due, strategy)

      updated =
        state
        |> Map.put(:entries, updated_entries)
        |> maybe_advance_revision(due)
        |> record({:expire_due, cutoff, limit, strategy, context})

      {{:ok, result_entries}, updated}
    end)
  end

  defp expire_entries(entries, due, :purge) do
    identifiers = MapSet.new(due, & &1.identifier)
    {due, Map.reject(entries, fn {identifier, _entry} -> identifier in identifiers end)}
  end

  defp expire_entries(entries, due, :retain) do
    expired = Enum.map(due, &%{&1 | state: :expired, version: &1.version + 1})
    updated = Enum.reduce(expired, entries, &Map.put(&2, &1.identifier, &1))
    {expired, updated}
  end

  defp due?(entry, cutoff, :purge), do: Registration.expired?(entry.registration, cutoff)

  defp due?(%Entry{state: :active} = entry, cutoff, :retain),
    do: Registration.expired?(entry.registration, cutoff)

  defp due?(%Entry{state: :expired}, _cutoff, :retain), do: false

  defp page(state, query, active_at, revision) do
    active_entries = active_entries(state, active_at)
    entries = Enum.slice(active_entries, query.offset, query.limit)
    consumed = query.offset + length(entries)
    next_offset = if consumed < length(active_entries), do: consumed

    {:ok,
     Page.new!(
       entries: entries,
       offset: query.offset,
       limit: query.limit,
       next_offset: next_offset,
       collection_revision: revision
     )}
  end

  defp listing_revision(state, nil, active_at) do
    {:ok, encode_revision(state.revision, active_at)}
  end

  defp listing_revision(state, revision, active_at) do
    with {:ok, expected_revision, snapshot_at} <- decode_revision(revision),
         true <- expected_revision == state.revision,
         true <- active_identifiers(state, snapshot_at) == active_identifiers(state, active_at) do
      {:ok, revision}
    else
      _changed_or_invalid -> :collection_changed
    end
  end

  defp active_entries(state, active_at) do
    state.entries
    |> Map.values()
    |> Enum.filter(&Entry.active?(&1, active_at))
    |> Enum.sort_by(& &1.identifier)
  end

  defp active_identifiers(state, active_at) do
    Enum.map(active_entries(state, active_at), & &1.identifier)
  end

  defp encode_revision(revision, active_at) do
    active_at_microseconds = DateTime.to_unix(active_at, :microsecond)
    "1:#{revision}:#{active_at_microseconds}"
  end

  defp decode_revision(revision) do
    with ["1", revision_value, active_at_value] <- String.split(revision, ":"),
         {revision, ""} when revision >= 0 <- Integer.parse(revision_value),
         {active_at_microseconds, ""} <- Integer.parse(active_at_value),
         {:ok, active_at} <- DateTime.from_unix(active_at_microseconds, :microsecond) do
      {:ok, revision, active_at}
    else
      _invalid -> :error
    end
  end

  defp put_entry(state, entry),
    do: Map.update!(state, :entries, &Map.put(&1, entry.identifier, entry))

  defp advance_revision(state), do: Map.update!(state, :revision, &(&1 + 1))
  defp maybe_advance_revision(state, []), do: state
  defp maybe_advance_revision(state, _entries), do: advance_revision(state)
  defp record(state, call), do: Map.update!(state, :calls, &[call | &1])
end
