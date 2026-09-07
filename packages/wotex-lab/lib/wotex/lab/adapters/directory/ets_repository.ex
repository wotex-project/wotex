defmodule Wotex.Lab.Adapters.Directory.EtsRepository do
  @moduledoc """
  Instance-owned ETS implementation of `Wotex.Directory.Repository`.

  A private `:ordered_set` table is owned by this process and every callback
  is one `GenServer.call`, so each unit of work is serialized and atomic with
  respect to every other caller. Identifiers are the table keys; Erlang term
  order on valid UTF-8 binaries is Unicode code point order, which is exactly
  the ascending order the keyset listing requires. The collection revision is
  a mutation counter that advances once per successful insert, replace, delete
  or entry-changing expiry batch. The store is volatile by design: when the
  owner stops, the table and its revision are gone. Persistence and reopen
  belong to the SQLite lane.

  The repository state handed to the directory is this process's pid.
  """

  use GenServer

  @behaviour Wotex.Directory.Repository

  alias Wotex.Directory.{Cursor, Entry, Page, Query, Registration}
  alias Wotex.Lab.Telemetry

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :id, :default)},
      start: {__MODULE__, :start_link, [opts]},
      restart: Keyword.get(opts, :restart, :transient),
      type: :worker
    }
  end

  @doc "Starts an empty store; `:name` is optional."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Returns call counters, the current revision, and the last repository context seen."
  @spec stats(pid()) :: map()
  def stats(repository), do: GenServer.call(repository, :stats)

  @impl Wotex.Directory.Repository
  def fetch(repository, identifier, context),
    do: span(:fetch, fn -> GenServer.call(repository, {:fetch, identifier, context}) end)

  @impl Wotex.Directory.Repository
  def insert(repository, %Entry{} = entry, context),
    do: span(:insert, fn -> GenServer.call(repository, {:insert, entry, context}) end)

  @impl Wotex.Directory.Repository
  def replace(repository, %Entry{} = entry, expected_version, context),
    do:
      span(:replace, fn ->
        GenServer.call(repository, {:replace, entry, expected_version, context})
      end)

  @impl Wotex.Directory.Repository
  def delete(repository, identifier, expected_version, context),
    do:
      span(:delete, fn ->
        GenServer.call(repository, {:delete, identifier, expected_version, context})
      end)

  @impl Wotex.Directory.Repository
  def list(repository, %Query{} = query, cursor, %DateTime{} = active_at, context),
    do:
      span(:list, fn -> GenServer.call(repository, {:list, query, cursor, active_at, context}) end)

  @impl Wotex.Directory.Repository
  def expire_due(repository, %DateTime{} = cutoff, limit, strategy, context),
    do:
      span(:expire_due, fn ->
        GenServer.call(repository, {:expire_due, cutoff, limit, strategy, context})
      end)

  defp span(operation, fun),
    do: Telemetry.span(:directory, :directory, %{operation: operation, profile: :ets}, fun)

  @impl GenServer
  def init(_opts) do
    table = :ets.new(__MODULE__, [:ordered_set, :private])
    {:ok, %{table: table, revision: 0, calls: %{}, last_context: nil}}
  end

  @impl GenServer
  def handle_call({:fetch, identifier, context}, _from, state) do
    result =
      case :ets.lookup(state.table, identifier) do
        [{^identifier, entry}] -> {:ok, entry}
        [] -> :not_found
      end

    {:reply, result, count(state, :fetch, context)}
  end

  def handle_call({:insert, entry, context}, _from, state) do
    if :ets.insert_new(state.table, {entry.identifier, Entry.for_storage(entry)}) do
      {:reply, {:ok, entry}, state |> advance() |> count(:insert, context)}
    else
      {:reply, {:error, :already_exists}, count(state, :insert, context)}
    end
  end

  def handle_call({:replace, entry, expected_version, context}, _from, state) do
    result =
      case :ets.lookup(state.table, entry.identifier) do
        [] ->
          {:error, :not_found}

        [{_identifier, %Entry{version: version}}] when version != expected_version ->
          {:error, :conflict}

        [{identifier, _existing}] ->
          true = :ets.insert(state.table, {identifier, Entry.for_storage(entry)})
          {:ok, entry}
      end

    {:reply, result, state |> advance_if(match?({:ok, _}, result)) |> count(:replace, context)}
  end

  def handle_call({:delete, identifier, expected_version, context}, _from, state) do
    result =
      case :ets.lookup(state.table, identifier) do
        [] ->
          {:error, :not_found}

        [{_identifier, %Entry{version: version}}] when version != expected_version ->
          {:error, :conflict}

        [{^identifier, _entry}] ->
          true = :ets.delete(state.table, identifier)
          :ok
      end

    {:reply, result, state |> advance_if(result == :ok) |> count(:delete, context)}
  end

  def handle_call({:list, query, cursor, active_at, context}, _from, state) do
    {:reply, page(state, query, cursor, active_at), count(state, :list, context)}
  end

  def handle_call({:expire_due, cutoff, limit, strategy, context}, _from, state) do
    due =
      state.table
      |> :ets.tab2list()
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&due?(&1, cutoff, strategy))
      |> Enum.take(limit)

    returned = Enum.map(due, &expire(&1, state.table, strategy))

    {:reply, {:ok, returned}, state |> advance_if(due != []) |> count(:expire_due, context)}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       calls: state.calls,
       revision: revision(state),
       size: :ets.info(state.table, :size),
       last_context: state.last_context
     }, state}
  end

  defp page(state, query, %Cursor{} = cursor, active_at) do
    if cursor.collection_revision == revision(state) do
      {:ok, keyset_page(state, query.limit, cursor.last_identifier, active_at)}
    else
      {:error, :collection_changed}
    end
  end

  defp page(state, query, nil, active_at) do
    {:ok, keyset_page(state, query.limit, nil, active_at)}
  end

  defp keyset_page(state, limit, after_identifier, active_at) do
    first =
      case after_identifier do
        nil -> :ets.first(state.table)
        identifier -> :ets.next(state.table, identifier)
      end

    entries = collect(state.table, first, active_at, limit + 1, [])

    Page.new!(
      entries: Enum.take(entries, limit),
      collection_revision: revision(state),
      more?: length(entries) > limit
    )
  end

  defp collect(_table, :"$end_of_table", _active_at, _remaining, acc), do: Enum.reverse(acc)
  defp collect(_table, _key, _active_at, 0, acc), do: Enum.reverse(acc)

  defp collect(table, key, active_at, remaining, acc) do
    [{^key, entry}] = :ets.lookup(table, key)
    next = :ets.next(table, key)

    if Entry.active?(entry, active_at),
      do: collect(table, next, active_at, remaining - 1, [entry | acc]),
      else: collect(table, next, active_at, remaining, acc)
  end

  defp due?(entry, cutoff, :purge), do: Registration.expired?(entry.registration, cutoff)

  defp due?(%Entry{state: :active} = entry, cutoff, :retain),
    do: Registration.expired?(entry.registration, cutoff)

  defp due?(%Entry{state: :expired}, _cutoff, :retain), do: false

  defp expire(entry, table, :purge) do
    true = :ets.delete(table, entry.identifier)
    entry
  end

  defp expire(entry, table, :retain) do
    expired = %{entry | state: :expired, version: entry.version + 1}
    true = :ets.insert(table, {entry.identifier, expired})
    expired
  end

  defp revision(state), do: "ets:" <> Integer.to_string(state.revision)
  defp advance(state), do: %{state | revision: state.revision + 1}
  defp advance_if(state, true), do: advance(state)
  defp advance_if(state, false), do: state

  defp count(state, callback, context) do
    %{state | calls: Map.update(state.calls, callback, 1, &(&1 + 1)), last_context: context}
  end
end
