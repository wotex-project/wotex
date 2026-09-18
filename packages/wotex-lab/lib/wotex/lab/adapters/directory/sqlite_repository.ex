# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Directory.Repository) and Code.ensure_loaded?(Exqlite.Sqlite3) do
  defmodule Wotex.Lab.Adapters.Directory.SqliteRepository do
    @moduledoc """
    Instance-owned SQLite implementation of `Wotex.Directory.Repository`.

    Mutations use Exqlite transactions and conditional SQL. One `GenServer` owns
    the connection and answers every callback, so the callbacks are serialized;
    SQLite supplies
    the atomicity, and the process supplies the ordering.

    ## Instance data directory

    The consumer names the directory explicitly with `:path`; nothing is derived
    from application configuration and loading Lab installs no schema. The file
    is `directory.sqlite3` under that directory unless `:database` names another
    plain file name. `start_link/1` creates the directory and the schema, so
    there is no migration step. `retain: false` removes the database file and its
    write-ahead siblings during orderly owner shutdown; the default keeps them, which
    is what the reopen path needs.

    ## Schema

        CREATE TABLE entries (
          identifier TEXT PRIMARY KEY NOT NULL COLLATE BINARY,
          version    INTEGER NOT NULL,
          state      TEXT NOT NULL CHECK (state IN ('active', 'expired')),
          expires_us INTEGER,
          document   BLOB NOT NULL
        ) WITHOUT ROWID

        CREATE TABLE collection (
          id       INTEGER PRIMARY KEY CHECK (id = 1),
          revision INTEGER NOT NULL
        )

    `identifier` is the primary key, so `insert/3` is an atomic conditional
    create that reports the unique-constraint failure as `:already_exists`.
    `version` supports the conditional `UPDATE`/`DELETE` of `replace/4` and
    `delete/4`: the precondition is part of the `WHERE` clause, and `changes()`
    separates an applied write from one that changed nothing. `expires_us` is the
    absolute expiry in microseconds since the epoch, which keeps activity and
    due selection inside SQL. `document` is the JSON envelope of the
    Thing Description and its registration information.

    Ordering is `ORDER BY identifier`. The default `BINARY` collation compares
    UTF-8 bytes, which is Unicode code point order, so `identifier > ?` is
    exactly the keyset continuation the listing contract requires.

    The collection revision lives in the `collection` table, so it survives a
    reopen. Every committed mutation advances it once; an expiry batch that
    selected nothing leaves it alone.

    ## Stored bytes are revalidated

    A read never trusts the stored document. Every row is rebuilt through
    `Wotex.ThingDescription.from_map/2`, `Wotex.Directory.Registration` and
    `Wotex.Directory.Entry.new/4`, and the reconstructed registration must
    re-serialize to the stored value. A row that fails is reported as
    `{:error, {:corrupt_entry, identifier}}` instead of being handed on.

    The repository state handed to the directory is this process's pid.
    """

    @behaviour Wotex.Directory.Repository

    use GenServer

    alias Exqlite.Sqlite3
    alias Wotex.Directory.{Cursor, Entry, Page, Query, Registration}
    alias Wotex.Lab.Telemetry
    alias Wotex.ThingDescription

    @database "directory.sqlite3"

    @pragmas [
      "PRAGMA journal_mode = WAL",
      "PRAGMA busy_timeout = 5000",
      "PRAGMA foreign_keys = ON"
    ]

    @tables [
      """
      CREATE TABLE IF NOT EXISTS entries (
        identifier TEXT PRIMARY KEY NOT NULL COLLATE BINARY,
        version INTEGER NOT NULL,
        state TEXT NOT NULL CHECK (state IN ('active', 'expired')),
        expires_us INTEGER,
        document BLOB NOT NULL
      ) WITHOUT ROWID
      """,
      """
      CREATE TABLE IF NOT EXISTS collection (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        revision INTEGER NOT NULL
      )
      """,
      "INSERT OR IGNORE INTO collection (id, revision) VALUES (1, 0)"
    ]

    @insert_sql """
    INSERT INTO entries (identifier, version, state, expires_us, document)
    VALUES (?1, ?2, ?3, ?4, ?5)
    """

    @replace_sql """
    UPDATE entries SET version = ?2, state = ?3, expires_us = ?4, document = ?5
    WHERE identifier = ?1 AND version = ?6
    """

    @fetch_sql "SELECT identifier, version, state, document FROM entries WHERE identifier = ?1"
    @delete_sql "DELETE FROM entries WHERE identifier = ?1 AND version = ?2"
    @exists_sql "SELECT 1 FROM entries WHERE identifier = ?1"
    @revision_sql "SELECT revision FROM collection WHERE id = 1"
    @advance_sql "UPDATE collection SET revision = revision + 1 WHERE id = 1"
    @size_sql "SELECT COUNT(*) FROM entries"
    @purge_one_sql "DELETE FROM entries WHERE identifier = ?1"

    @retain_one_sql """
    UPDATE entries SET state = 'expired', version = version + 1 WHERE identifier = ?1
    """

    @list_sql """
    SELECT identifier, version, state, document FROM entries
    WHERE identifier > ?1 AND state = 'active' AND (expires_us IS NULL OR expires_us > ?2)
    ORDER BY identifier ASC LIMIT ?3
    """

    @purge_due_sql """
    SELECT identifier, version, state, document FROM entries
    WHERE expires_us IS NOT NULL AND expires_us <= ?1
    ORDER BY identifier ASC LIMIT ?2
    """

    @retain_due_sql """
    SELECT identifier, version, state, document FROM entries
    WHERE state = 'active' AND expires_us IS NOT NULL AND expires_us <= ?1
    ORDER BY identifier ASC LIMIT ?2
    """

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

    @doc """
    Starts a store over the instance data directory named by `:path`.

    `:database` names the file inside that directory, `:retain` decides whether
    the file survives termination, and `:name` is optional. The directory and the
    schema are created here, never by loading the library.
    """
    @spec start_link(keyword()) :: GenServer.on_start() | {:error, term()}
    def start_link(opts \\ []) do
      with {:ok, file} <- database_file(opts),
           :ok <- File.mkdir_p(Path.dirname(file)) do
        start_server(%{file: file, retain?: Keyword.get(opts, :retain, true)}, opts)
      end
    end

    @doc "Returns call counters, the current revision, the row count and the last context seen."
    @spec stats(GenServer.server()) :: map()
    def stats(repository), do: GenServer.call(repository, :stats)

    @doc "Returns the absolute path of the database file this store owns."
    @spec database_path(GenServer.server()) :: String.t()
    def database_path(repository), do: GenServer.call(repository, :database_path)

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
      do: Telemetry.span(:directory, :directory, %{operation: operation, profile: :sqlite}, fun)

    @impl GenServer
    def init(config) do
      Process.flag(:trap_exit, true)

      with {:ok, connection} <- Sqlite3.open(config.file),
           :ok <- create_schema(connection) do
        {:ok,
         %{
           connection: connection,
           file: config.file,
           retain?: config.retain?,
           calls: %{},
           last_context: nil
         }}
      else
        {:error, reason} -> {:stop, {:sqlite, reason}}
      end
    end

    @impl GenServer
    def handle_call({:fetch, identifier, context}, _, state) do
      result =
        case run_query(state.connection, @fetch_sql, [identifier]) do
          {:ok, [row]} -> decode_entry(row)
          {:ok, []} -> :not_found
          {:error, reason} -> {:error, reason}
        end

      {:reply, result, count(state, :fetch, context)}
    end

    def handle_call({:insert, entry, context}, _, state) do
      reply = write(state, fn connection -> insert_work(connection, entry) end)
      {:reply, reply, count(state, :insert, context)}
    end

    def handle_call({:replace, entry, expected_version, context}, _, state) do
      reply = write(state, fn connection -> replace_work(connection, entry, expected_version) end)
      {:reply, reply, count(state, :replace, context)}
    end

    def handle_call({:delete, identifier, expected_version, context}, _, state) do
      reply =
        write(state, fn connection -> delete_work(connection, identifier, expected_version) end)

      {:reply, reply, count(state, :delete, context)}
    end

    def handle_call({:list, query, cursor, active_at, context}, _, state) do
      reply =
        read(state, fn connection -> list_work(connection, query, cursor, active_at) end)

      {:reply, reply, count(state, :list, context)}
    end

    def handle_call({:expire_due, cutoff, limit, strategy, context}, _, state) do
      reply = write(state, fn connection -> expire_work(connection, cutoff, limit, strategy) end)
      {:reply, reply, count(state, :expire_due, context)}
    end

    def handle_call(:stats, _, state) do
      {:ok, [[revision]]} = run_query(state.connection, @revision_sql, [])
      {:ok, [[size]]} = run_query(state.connection, @size_sql, [])

      {:reply,
       %{
         calls: state.calls,
         revision: revision_value(revision),
         size: size,
         last_context: state.last_context
       }, state}
    end

    def handle_call(:database_path, _, state), do: {:reply, state.file, state}

    @impl GenServer
    def terminate(_, state) do
      _ = Sqlite3.close(state.connection)
      teardown(state.retain?, state.file)
    end

    defp start_server(config, opts) do
      case Keyword.get(opts, :name) do
        nil -> GenServer.start_link(__MODULE__, config)
        name -> GenServer.start_link(__MODULE__, config, name: name)
      end
    end

    defp database_file(opts) do
      path = Keyword.get(opts, :path)
      file = Keyword.get(opts, :database, @database)

      if is_binary(path) and path != "" and plain_file_name?(file) do
        {:ok, Path.join(path, file)}
      else
        {:error, :invalid_data_directory}
      end
    end

    defp plain_file_name?(file) do
      is_binary(file) and file not in ["", ".", ".."] and Path.basename(file) == file
    end

    defp create_schema(connection) do
      Enum.reduce_while(@pragmas ++ @tables, :ok, fn statement, :ok ->
        case Sqlite3.execute(connection, statement) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end

    defp teardown(true, _), do: :ok

    defp teardown(false, file) do
      Enum.each([file, file <> "-wal", file <> "-shm"], fn path -> _ = File.rm(path) end)
    end

    defp write(state, work), do: transaction(state.connection, "BEGIN IMMEDIATE", work)
    defp read(state, work), do: transaction(state.connection, "BEGIN DEFERRED", work)

    defp transaction(connection, begin_statement, work) do
      case Sqlite3.execute(connection, begin_statement) do
        :ok -> finish(connection, work.(connection))
        {:error, reason} -> {:error, {:sqlite, reason}}
      end
    end

    defp finish(connection, {:commit, reply}) do
      case Sqlite3.execute(connection, "COMMIT") do
        :ok -> reply
        {:error, reason} -> undo(connection, {:error, {:sqlite, reason}})
      end
    end

    defp finish(connection, {:rollback, reply}), do: undo(connection, reply)

    defp undo(connection, reply) do
      _ = Sqlite3.execute(connection, "ROLLBACK")
      reply
    end

    defp insert_work(connection, entry) do
      case mutate(connection, @insert_sql, entry_params(entry)) do
        {:ok, 1} -> advance_revision(connection, {:ok, entry})
        {:error, reason} -> {:rollback, {:error, insert_reason(reason)}}
      end
    end

    defp insert_reason({:sqlite, "UNIQUE constraint failed" <> _}), do: :already_exists
    defp insert_reason(reason), do: reason

    defp replace_work(connection, entry, expected_version) do
      params = Enum.concat(entry_params(entry), [expected_version])

      case mutate(connection, @replace_sql, params) do
        {:ok, 1} -> advance_revision(connection, {:ok, entry})
        {:ok, 0} -> {:rollback, missing_or_conflict(connection, entry.identifier)}
        {:error, reason} -> {:rollback, {:error, reason}}
      end
    end

    defp delete_work(connection, identifier, expected_version) do
      case mutate(connection, @delete_sql, [identifier, expected_version]) do
        {:ok, 1} -> advance_revision(connection, :ok)
        {:ok, 0} -> {:rollback, missing_or_conflict(connection, identifier)}
        {:error, reason} -> {:rollback, {:error, reason}}
      end
    end

    defp missing_or_conflict(connection, identifier) do
      case run_query(connection, @exists_sql, [identifier]) do
        {:ok, []} -> {:error, :not_found}
        {:ok, _} -> {:error, :conflict}
        {:error, reason} -> {:error, reason}
      end
    end

    defp advance_revision(connection, reply) do
      case mutate(connection, @advance_sql, []) do
        {:ok, _} -> {:commit, reply}
        {:error, reason} -> {:rollback, {:error, reason}}
      end
    end

    defp list_work(connection, listing, cursor, active_at) do
      case run_query(connection, @revision_sql, []) do
        {:ok, [[revision]]} -> list_page(connection, listing, cursor, active_at, revision)
        {:error, reason} -> {:commit, {:error, reason}}
      end
    end

    defp list_page(connection, listing, cursor, active_at, revision) do
      current = revision_value(revision)

      if continues?(cursor, current) do
        select_page(connection, listing, cursor, active_at, current)
      else
        {:commit, {:error, :collection_changed}}
      end
    end

    defp continues?(nil, _), do: true
    defp continues?(%Cursor{collection_revision: bound}, current), do: bound == current

    defp select_page(connection, listing, cursor, active_at, revision) do
      active_us = DateTime.to_unix(active_at, :microsecond)
      params = [last_identifier(cursor), active_us, listing.limit + 1]

      with {:ok, rows} <- run_query(connection, @list_sql, params),
           {:ok, entries} <- decode_entries(rows) do
        {:commit, {:ok, bounded_page(entries, listing.limit, revision)}}
      else
        {:error, reason} -> {:commit, {:error, reason}}
      end
    end

    defp bounded_page(entries, limit, revision) do
      Page.new!(
        entries: Enum.take(entries, limit),
        collection_revision: revision,
        more?: length(entries) > limit
      )
    end

    defp last_identifier(nil), do: ""
    defp last_identifier(%Cursor{last_identifier: identifier}), do: identifier

    defp expire_work(connection, cutoff, limit, strategy) do
      params = [DateTime.to_unix(cutoff, :microsecond), limit]

      with {:ok, rows} <- run_query(connection, due_sql(strategy), params),
           {:ok, entries} <- decode_entries(rows) do
        apply_expiry(connection, entries, strategy)
      else
        {:error, reason} -> {:rollback, {:error, reason}}
      end
    end

    defp due_sql(:purge), do: @purge_due_sql
    defp due_sql(:retain), do: @retain_due_sql

    defp apply_expiry(_, [], _), do: {:commit, {:ok, []}}

    defp apply_expiry(connection, entries, strategy) do
      expired =
        Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
          expire_one(connection, entry, strategy, acc)
        end)

      case expired do
        {:ok, acc} -> advance_revision(connection, {:ok, Enum.reverse(acc)})
        {:error, reason} -> {:rollback, {:error, reason}}
      end
    end

    defp expire_one(connection, entry, :purge, acc) do
      case mutate(connection, @purge_one_sql, [entry.identifier]) do
        {:ok, 1} -> {:cont, {:ok, [entry | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end

    defp expire_one(connection, entry, :retain, acc) do
      case mutate(connection, @retain_one_sql, [entry.identifier]) do
        {:ok, 1} -> {:cont, {:ok, [expired_entry(entry) | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end

    defp expired_entry(entry), do: %{entry | state: :expired, version: entry.version + 1}

    defp entry_params(entry) do
      stored = Entry.for_storage(entry)

      [
        stored.identifier,
        stored.version,
        Atom.to_string(stored.state),
        expires_us(stored.registration),
        {:blob, document(stored)}
      ]
    end

    defp expires_us(%Registration{expires: nil}), do: nil
    defp expires_us(%Registration{expires: expires}), do: DateTime.to_unix(expires, :microsecond)

    defp document(entry) do
      JSON.encode!(%{
        "thingDescription" => ThingDescription.to_map(entry.thing_description),
        "registration" => Registration.to_map(entry.registration)
      })
    end

    defp decode_entries(rows) do
      decoded =
        Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
          case decode_entry(row) do
            {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case decoded do
        {:ok, entries} -> {:ok, Enum.reverse(entries)}
        {:error, reason} -> {:error, reason}
      end
    end

    defp decode_entry([identifier, version, state, document]) do
      with {:ok, %{"thingDescription" => raw_td, "registration" => raw_registration}} <-
             JSON.decode(document),
           {:ok, thing_description} <- ThingDescription.from_map(raw_td),
           {:ok, registration} <- decode_registration(raw_registration),
           {:ok, entry_state} <- decode_state(state),
           {:ok, entry} <-
             Entry.new(identifier, thing_description, registration,
               version: version,
               state: entry_state
             ) do
        {:ok, entry}
      else
        _ -> {:error, {:corrupt_entry, identifier}}
      end
    end

    defp decode_registration(%{"created" => created, "modified" => modified} = raw) do
      values = Map.drop(raw, ["created", "modified", "retrieved"])

      with {:ok, created_at, 0} <- DateTime.from_iso8601(created),
           {:ok, modified_at, 0} <- DateTime.from_iso8601(modified),
           {:ok, initial} <- Registration.create(created_at, {:present, values}, :service),
           {:ok, registration} <-
             Registration.refresh(initial, modified_at, {:present, values}, :service),
           true <- Registration.to_map(registration) == raw do
        {:ok, registration}
      else
        _ -> :error
      end
    end

    defp decode_registration(_), do: :error

    defp decode_state("active"), do: {:ok, :active}
    defp decode_state("expired"), do: {:ok, :expired}
    defp decode_state(_), do: :error

    defp revision_value(revision), do: "sqlite:" <> Integer.to_string(revision)

    defp run_query(connection, sql, params) do
      with_statement(connection, sql, params, fn statement ->
        case Sqlite3.fetch_all(connection, statement) do
          {:ok, rows} -> {:ok, rows}
          {:error, reason} -> {:error, {:sqlite, reason}}
        end
      end)
    end

    defp mutate(connection, sql, params) do
      with_statement(connection, sql, params, fn statement ->
        case Sqlite3.step(connection, statement) do
          :done -> Sqlite3.changes(connection)
          other -> {:error, {:sqlite, step_reason(other)}}
        end
      end)
    end

    defp step_reason({:error, reason}), do: reason
    defp step_reason(other), do: other

    defp with_statement(connection, sql, params, work) do
      case Sqlite3.prepare(connection, sql) do
        {:ok, statement} -> run_statement(connection, statement, params, work)
        {:error, reason} -> {:error, {:sqlite, reason}}
      end
    end

    defp run_statement(connection, statement, params, work) do
      :ok = Sqlite3.bind(statement, params)
      result = work.(statement)
      _ = Sqlite3.release(connection, statement)
      result
    end

    defp count(state, callback, context) do
      %{state | calls: Map.update(state.calls, callback, 1, &(&1 + 1)), last_context: context}
    end
  end
end
