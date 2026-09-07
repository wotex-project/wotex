defmodule Wotex.Directory.MemoryRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  alias Wotex.Directory.{Cursor, Entry, Page, Query, Registration}

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
  def list(agent, %Query{} = query, cursor, active_at, context) do
    Agent.get_and_update(agent, fn state ->
      {page(state, query, cursor, active_at), record(state, {:list, query, cursor, context})}
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

  defp page(state, query, nil, active_at) do
    {:ok, bounded_page(active_entries(state, active_at), query.limit, revision(state))}
  end

  defp page(state, query, %Cursor{} = cursor, active_at) do
    revision = revision(state)

    if cursor.collection_revision == revision do
      remaining =
        state
        |> active_entries(active_at)
        |> Enum.filter(&(&1.identifier > cursor.last_identifier))

      {:ok, bounded_page(remaining, query.limit, revision)}
    else
      {:error, :collection_changed}
    end
  end

  defp bounded_page(entries, limit, revision) do
    Page.new!(
      entries: Enum.take(entries, limit),
      collection_revision: revision,
      more?: length(entries) > limit
    )
  end

  defp revision(state), do: "generation:" <> Integer.to_string(state.revision)

  defp active_entries(state, active_at) do
    state.entries
    |> Map.values()
    |> Enum.filter(&Entry.active?(&1, active_at))
    |> Enum.sort_by(& &1.identifier)
  end

  defp put_entry(state, entry),
    do: Map.update!(state, :entries, &Map.put(&1, entry.identifier, entry))

  defp advance_revision(state), do: Map.update!(state, :revision, &(&1 + 1))
  defp maybe_advance_revision(state, []), do: state
  defp maybe_advance_revision(state, _entries), do: advance_revision(state)
  defp record(state, call), do: Map.update!(state, :calls, &[call | &1])
end
