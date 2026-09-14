defmodule Wotex.Directory.TableRepository do
  @moduledoc false

  @behaviour Wotex.Directory.Repository

  alias Wotex.Directory.Page

  @spec new([term()]) :: :ets.tid()
  def new(contexts) do
    table = :ets.new(__MODULE__, [:set, :public])
    for context <- contexts, do: :ets.insert(table, {context, 0, []})
    table
  end

  @impl true
  def fetch(table, identifier, context) do
    {_, entries} = snapshot(table, context)

    case List.keyfind(entries, identifier, 0) do
      nil -> {:error, :not_found}
      {_, entry} -> {:ok, entry}
    end
  end

  @impl true
  def insert(table, entry, context) do
    transaction(table, context, fn entries ->
      if List.keymember?(entries, entry.identifier, 0) do
        {:read, {:error, :already_exists}}
      else
        {:write, {:ok, entry}, [{entry.identifier, entry} | entries]}
      end
    end)
  end

  @impl true
  def replace(table, entry, expected_version, context) do
    transaction(table, context, fn entries ->
      case expected(entries, entry.identifier, expected_version) do
        :ok ->
          {:write, {:ok, entry},
           List.keyreplace(entries, entry.identifier, 0, {entry.identifier, entry})}

        error ->
          {:read, error}
      end
    end)
  end

  @impl true
  def delete(table, identifier, expected_version, context) do
    transaction(table, context, fn entries ->
      case expected(entries, identifier, expected_version) do
        :ok -> {:write, :ok, List.keydelete(entries, identifier, 0)}
        error -> {:read, error}
      end
    end)
  end

  @impl true
  def list(table, query, cursor, active_at, context) do
    {generation, entries} = snapshot(table, context)
    revision = "table:" <> Integer.to_string(generation)

    if cursor != nil and cursor.collection_revision != revision do
      {:error, :collection_changed}
    else
      selected =
        for {identifier, entry} <- Enum.sort(entries),
            entry.state == :active,
            not due?(entry, active_at),
            cursor == nil or identifier > cursor.last_identifier,
            do: entry

      Page.new(
        entries: Enum.take(selected, query.limit),
        more?: length(selected) > query.limit,
        collection_revision: revision
      )
    end
  end

  @impl true
  def expire_due(table, cutoff, limit, strategy, context) do
    transaction(table, context, fn entries ->
      due =
        entries
        |> Enum.sort()
        |> Enum.filter(fn {_, entry} ->
          due?(entry, cutoff) and (strategy == :purge or entry.state == :active)
        end)
        |> Enum.take(limit)

      expire(entries, due, strategy)
    end)
  end

  defp expected(entries, identifier, expected_version) do
    case List.keyfind(entries, identifier, 0) do
      nil -> {:error, :not_found}
      {_, %{version: ^expected_version}} -> :ok
      _ -> {:error, :conflict}
    end
  end

  defp due?(%{registration: %{expires: nil}}, _), do: false

  defp due?(%{registration: %{expires: expires}}, cutoff),
    do: DateTime.compare(expires, cutoff) != :gt

  defp expire(_, [], _), do: {:read, {:ok, []}}

  defp expire(entries, due, :purge) do
    remaining = Enum.reduce(due, entries, fn {id, _}, values -> List.keydelete(values, id, 0) end)
    {:write, {:ok, Enum.map(due, &elem(&1, 1))}, remaining}
  end

  defp expire(entries, due, :retain) do
    retained =
      Enum.map(due, fn {_, entry} -> %{entry | state: :expired, version: entry.version + 1} end)

    remaining =
      Enum.reduce(retained, entries, fn entry, values ->
        List.keyreplace(values, entry.identifier, 0, {entry.identifier, entry})
      end)

    {:write, {:ok, retained}, remaining}
  end

  defp snapshot(table, context) do
    [{^context, generation, entries}] = :ets.lookup(table, context)
    {generation, entries}
  end

  defp transaction(table, context, operation) do
    {generation, entries} = snapshot(table, context)

    case operation.(entries) do
      {:read, result} ->
        result

      {:write, result, updated} ->
        replacement = {context, generation + 1, updated}
        specification = [{{context, generation, :_}, [], [{:const, replacement}]}]

        case :ets.select_replace(table, specification) do
          1 -> result
          0 -> transaction(table, context, operation)
        end
    end
  end
end
