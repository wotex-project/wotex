defmodule Wotex.Lab.DirectoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Exqlite.Sqlite3
  alias Wotex.Directory
  alias Wotex.Directory.{Context, Error, Event, Expiry, Mutation, Page, Query, Service}
  alias Wotex.Lab

  alias Wotex.Lab.Adapters.Directory.{
    Authorization,
    Clock,
    EtsRepository,
    Identifier,
    SqliteRepository
  }

  alias Wotex.ThingDescription

  @start ~U[2026-09-07 12:00:00Z]
  @stores [:ets, :sqlite]

  for store <- @stores do
    describe "#{store} store" do
      @describetag :tmp_dir
      @describetag store: store

      setup context do
        start_directory(context)
      end

      test "register, get, replace, patch, delete and events work through the public ports", %{
        service: service,
        context: context,
        module: module,
        repository: repository
      } do
        assert {:ok, %Mutation{status: :created, entry: created}} =
                 Directory.register(service, thing("urn:wotex:lab:room:1"), context)

        assert created.version == 1

        assert {:ok, event} =
                 Event.from_mutation(
                   %Mutation{status: :created, entry: created, operation: :register},
                   []
                 )

        assert event.type == :thing_created

        assert {:ok, fetched} = Directory.get(service, "urn:wotex:lab:room:1", context)
        assert fetched.identifier == "urn:wotex:lab:room:1"
        assert fetched.registration.retrieved == @start

        assert {:ok, %Mutation{status: :replaced, entry: replaced}} =
                 Directory.register(
                   service,
                   thing("urn:wotex:lab:room:1", %{"title" => "Renamed"}),
                   context
                 )

        assert replaced.version == 2

        assert {:ok, %Mutation{status: :patched, entry: patched}} =
                 Directory.patch(
                   service,
                   "urn:wotex:lab:room:1",
                   %{"title" => "Patched"},
                   context
                 )

        assert patched.version == 3
        assert ThingDescription.to_map(patched.thing_description)["title"] == "Patched"

        assert {:ok, %Mutation{status: :created, entry: anonymous}} =
                 Directory.register(service, thing(nil), context)

        assert anonymous.identifier == "urn:wotex:lab:thing:1"

        assert {:ok, %Mutation{status: :deleted}} =
                 Directory.delete(service, anonymous.identifier, context)

        assert {:error, %Error{code: :not_found}} =
                 Directory.get(service, anonymous.identifier, context)

        assert %{calls: calls, last_context: {:tenant, "room-1"}, size: 1} =
                 module.stats(repository)

        assert calls.insert == 2 and calls.delete == 1 and calls.replace == 2
        assert {:ok, introduction} = Directory.introduction(service)
        assert introduction.thing_description == thing("urn:wotex:lab:directory")
      end

      test "authorization runs before any repository access and separates principals", %{
        module: module,
        repository: repository,
        clock: clock
      } do
        policy = %{
          reader: [:get, :list],
          writer: {:tenant, "room-1", [:register, :get, :replace, :patch, :delete, :list, :expire]}
        }

        {:ok, identifier} = Identifier.start_link()
        service = scoped_service(module, repository, clock, identifier, policy)

        stranger = Context.new!(:stranger)
        reader = Context.new!(:reader)
        writer = Context.new!(:writer, authorization: {:tenant, "room-1"})
        wrong_tenant = Context.new!(:writer, authorization: {:tenant, "room-2"})

        assert {:error, %Error{code: :forbidden}} =
                 Directory.register(service, thing("urn:x:1"), stranger)

        assert {:error, %Error{code: :forbidden}} =
                 Directory.register(service, thing("urn:x:1"), reader)

        assert {:error, %Error{code: :forbidden}} =
                 Directory.register(service, thing("urn:x:1"), wrong_tenant)

        assert %{calls: calls} = module.stats(repository)
        refute Map.has_key?(calls, :insert)

        assert {:ok, _} = Directory.register(service, thing("urn:x:1"), writer)
        assert {:ok, _} = Directory.get(service, "urn:x:1", reader)
        assert {:error, %Error{code: :forbidden}} = Directory.delete(service, "urn:x:1", reader)

        broken = scoped_service(module, repository, clock, identifier, :not_a_policy)
        assert {:error, %Error{phase: :authorization}} = Directory.get(broken, "urn:x:1", reader)
      end

      test "competing conditional writes have exactly one winner", %{
        service: service,
        context: context
      } do
        {:ok, %Mutation{entry: entry}} =
          Directory.register(service, thing("urn:wotex:lab:race:1"), context)

        results =
          1..8
          |> Task.async_stream(fn n ->
            Directory.replace(
              service,
              "urn:wotex:lab:race:1",
              thing("urn:wotex:lab:race:1", %{"title" => "writer-#{n}"}),
              context,
              if_version: entry.version
            )
          end)
          |> Enum.map(fn {:ok, result} -> result end)

        assert Enum.count(results, &match?({:ok, _mutation}, &1)) == 1
        assert Enum.count(results, &match?({:error, %Error{code: :conflict}}, &1)) == 7
        assert {:ok, %{version: 2}} = Directory.get(service, "urn:wotex:lab:race:1", context)

        assert {:error, %Error{code: :conflict}} =
                 Directory.delete(service, "urn:wotex:lab:race:1", context, if_version: 1)

        assert {:ok, _} =
                 Directory.delete(service, "urn:wotex:lab:race:1", context, if_version: 2)
      end

      test "listing pages by keyset in stable order and survives expiry drift but not mutation",
           %{service: service, context: context, clock: clock} do
        for suffix <- ["c", "a", "e", "b", "d"] do
          ttl = if suffix == "b", do: %{"registration" => %{"ttl" => 30}}, else: %{}

          {:ok, _} =
            Directory.register(service, thing("urn:wotex:lab:list:" <> suffix, ttl), context)
        end

        assert {:ok, %Page{entries: [first, second], next_cursor: cursor}} =
                 Directory.list(service, context)

        assert Enum.map([first, second], & &1.identifier) == [
                 "urn:wotex:lab:list:a",
                 "urn:wotex:lab:list:b"
               ]

        assert is_binary(cursor)

        Clock.advance(clock, 60)

        assert {:ok, %Page{entries: entries, next_cursor: last_cursor}} =
                 Directory.list(service, context, cursor: cursor, limit: 4)

        assert Enum.map(entries, & &1.identifier) == [
                 "urn:wotex:lab:list:c",
                 "urn:wotex:lab:list:d",
                 "urn:wotex:lab:list:e"
               ]

        assert last_cursor == nil

        assert {:ok, %Page{entries: fresh}} = Directory.list(service, context, limit: 4)
        refute Enum.any?(fresh, &(&1.identifier == "urn:wotex:lab:list:b"))

        {:ok, %Page{next_cursor: stale}} = Directory.list(service, context)
        {:ok, _} = Directory.register(service, thing("urn:wotex:lab:list:f"), context)

        assert {:error, %Error{code: :collection_changed}} =
                 Directory.list(service, context, cursor: stale)

        assert {:error, %Error{code: :invalid_request}} =
                 Directory.list(service, context, cursor: "bogus")

        assert {:error, %Error{code: :invalid_request}} =
                 Directory.list(service, context, limit: 99)
      end

      test "expiry is bounded, repeatable, and honors purge and retain", %{
        service: service,
        context: context,
        clock: clock,
        module: module,
        repository: repository
      } do
        for n <- 1..5 do
          {:ok, _} =
            Directory.register(
              service,
              thing("urn:wotex:lab:ttl:#{n}", %{"registration" => %{"ttl" => n * 10}}),
              context
            )
        end

        assert {:ok, %Expiry{entries: []}} = Directory.expire(service, context)
        Clock.advance(clock, 35)

        assert {:ok, %Expiry{strategy: :purge, entries: [one, two]}} =
                 Directory.expire(service, context)

        assert Enum.map([one, two], & &1.identifier) == [
                 "urn:wotex:lab:ttl:1",
                 "urn:wotex:lab:ttl:2"
               ]

        assert {:ok, %Expiry{entries: [three]}} = Directory.expire(service, context, limit: 4)
        assert three.identifier == "urn:wotex:lab:ttl:3"
        assert {:ok, %Expiry{entries: []}} = Directory.expire(service, context)
        assert %{size: 2} = module.stats(repository)

        Clock.advance(clock, 100)

        assert {:ok, %Expiry{strategy: :retain, entries: [four, five]}} =
                 Directory.expire(service, context, strategy: :retain)

        assert Enum.all?([four, five], &(&1.state == :expired and &1.version == 2))
        assert {:ok, %Expiry{entries: []}} = Directory.expire(service, context, strategy: :retain)
        assert {:error, %Error{code: :expired}} = Directory.get(service, four.identifier, context)
        assert %{size: 2} = module.stats(repository)

        assert {:ok, %Expiry{entries: [_, _]}} =
                 Directory.expire(service, context, strategy: :purge)

        assert %{size: 0} = module.stats(repository)
      end

      test "an entry-changing expiry batch invalidates a cursor issued before it", %{
        service: service,
        context: context,
        clock: clock
      } do
        for n <- 1..4 do
          {:ok, _} =
            Directory.register(
              service,
              thing("urn:wotex:lab:drift:#{n}", %{"registration" => %{"ttl" => 30}}),
              context
            )
        end

        {:ok, %Page{next_cursor: cursor}} = Directory.list(service, context)
        assert {:ok, %Page{entries: [_, _]}} = Directory.list(service, context, cursor: cursor)

        Clock.advance(clock, 60)
        assert {:ok, %Expiry{entries: [_, _]}} = Directory.expire(service, context)

        assert {:error, %Error{code: :collection_changed}} =
                 Directory.list(service, context, cursor: cursor)
      end

      test "the repository callbacks report absence, conflict and collisions directly", %{
        module: module,
        repository: repository,
        service: service,
        context: context,
        tmp_dir: tmp_dir
      } do
        name = {:global, {module, make_ref()}}
        {:ok, named} = start_named(module, name, tmp_dir)
        assert GenServer.whereis(name) == named

        {:ok, %Mutation{entry: entry}} =
          Directory.register(service, thing("urn:wotex:lab:direct:1"), context)

        assert :not_found = module.fetch(repository, "urn:none", nil)

        assert {:error, :not_found} =
                 module.replace(repository, %{entry | identifier: "urn:none"}, 1, nil)

        assert {:error, :not_found} = module.delete(repository, "urn:none", 1, nil)
        assert {:error, :already_exists} = module.insert(repository, entry, nil)
        assert {:error, :conflict} = module.replace(repository, entry, 2, nil)
        assert {:error, :conflict} = module.delete(repository, entry.identifier, 2, nil)
        assert :ok = module.delete(repository, entry.identifier, 1, nil)
      end
    end
  end

  describe "ets store volatility" do
    @describetag store: :ets
    @describetag :tmp_dir

    setup context do
      start_directory(context)
    end

    test "a restarted owner starts empty with a fresh revision", %{
      lab: lab,
      service: service,
      context: context,
      repository: repository
    } do
      {:ok, _} = Directory.register(service, thing("urn:wotex:lab:volatile:1"), context)
      assert %{revision: "ets:1"} = EtsRepository.stats(repository)

      monitor = Process.monitor(repository)
      Process.exit(repository, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^repository, :killed}

      {:ok, replacement} = Lab.start_child(lab, :things, {EtsRepository, id: :replacement})
      assert %{revision: "ets:0", size: 0} = EtsRepository.stats(replacement)
      assert {:ok, [_, _]} = {:ok, Enum.take(Supervisor.which_children(lab), 2)}
    end
  end

  describe "sqlite store durability" do
    @describetag store: :sqlite
    @describetag :tmp_dir

    setup context do
      start_directory(context)
    end

    test "an aborted statement rolls the whole transaction back", %{
      service: service,
      context: context,
      repository: repository
    } do
      {:ok, _} = Directory.register(service, thing("urn:wotex:lab:tx:1"), context)
      assert %{revision: "sqlite:1", size: 1} = SqliteRepository.stats(repository)

      connection = open_database(repository)

      :ok =
        Sqlite3.execute(
          connection,
          "CREATE TRIGGER injected BEFORE UPDATE ON collection " <>
            "BEGIN SELECT RAISE(ABORT, 'injected failure'); END"
        )

      assert {:error, %Error{code: :repository_failure}} =
               Directory.register(service, thing("urn:wotex:lab:tx:2"), context)

      assert %{revision: "sqlite:1", size: 1} = SqliteRepository.stats(repository)
      assert :not_found = SqliteRepository.fetch(repository, "urn:wotex:lab:tx:2", nil)

      :ok = Sqlite3.execute(connection, "DROP TRIGGER injected")

      assert {:ok, %Mutation{status: :created}} =
               Directory.register(service, thing("urn:wotex:lab:tx:2"), context)

      assert %{revision: "sqlite:2", size: 2} = SqliteRepository.stats(repository)
    end

    test "a stopped owner reopens the same file with its entries and revision", %{
      service: service,
      context: context,
      repository: repository,
      tmp_dir: tmp_dir
    } do
      {:ok, _} = Directory.register(service, thing("urn:wotex:lab:durable:1"), context)
      {:ok, _} = Directory.register(service, thing("urn:wotex:lab:durable:2"), context)
      file = SqliteRepository.database_path(repository)

      :ok = GenServer.stop(repository)
      assert File.exists?(file)

      {:ok, reopened} = SqliteRepository.start_link(path: tmp_dir)
      assert %{revision: "sqlite:2", size: 2} = SqliteRepository.stats(reopened)
      assert {:ok, entry} = SqliteRepository.fetch(reopened, "urn:wotex:lab:durable:2", nil)
      assert entry.version == 1
      assert ThingDescription.to_map(entry.thing_description)["title"] == "Lab Thing"
    end

    test "every mutating unit of work reports an aborted statement without writing", %{
      service: service,
      context: context,
      repository: repository
    } do
      {:ok, %Mutation{entry: entry}} =
        Directory.register(service, thing("urn:wotex:lab:abort:1"), context)

      {:ok, _} =
        Directory.register(
          service,
          thing("urn:wotex:lab:abort:2", %{"registration" => %{"ttl" => 1}}),
          context
        )

      connection = open_database(repository)
      Enum.each(["INSERT", "UPDATE", "DELETE"], &inject_abort(connection, &1))
      cutoff = DateTime.add(@start, 60, :second)

      assert {:error, {:sqlite, "injected"}} = SqliteRepository.insert(repository, entry, nil)
      assert {:error, {:sqlite, "injected"}} = SqliteRepository.replace(repository, entry, 1, nil)

      assert {:error, {:sqlite, "injected"}} =
               SqliteRepository.delete(repository, entry.identifier, 1, nil)

      assert {:error, {:sqlite, "injected"}} =
               SqliteRepository.expire_due(repository, cutoff, 2, :purge, nil)

      assert {:error, {:sqlite, "injected"}} =
               SqliteRepository.expire_due(repository, cutoff, 2, :retain, nil)

      assert %{revision: "sqlite:2", size: 2} = SqliteRepository.stats(repository)
    end

    test "a missing table is reported rather than hidden", %{
      service: service,
      context: context,
      repository: repository
    } do
      {:ok, _} = Directory.register(service, thing("urn:wotex:lab:missing:1"), context)
      connection = open_database(repository)
      {:ok, query} = Query.new([limit: 2], [])

      :ok = Sqlite3.execute(connection, "DROP TABLE collection")

      assert {:error, {:sqlite, _}} =
               SqliteRepository.list(repository, query, nil, @start, nil)

      :ok = Sqlite3.execute(connection, "DROP TABLE entries")

      assert {:error, {:sqlite, _}} =
               SqliteRepository.fetch(repository, "urn:wotex:lab:missing:1", nil)

      assert {:error, {:sqlite, _}} =
               SqliteRepository.expire_due(repository, @start, 2, :purge, nil)
    end

    test "a corrupted stored document is revalidated and rejected", %{
      service: service,
      context: context,
      repository: repository
    } do
      {:ok, _} = Directory.register(service, thing("urn:wotex:lab:corrupt:1"), context)
      connection = open_database(repository)

      overwrite(connection, "urn:wotex:lab:corrupt:1", ~s({"registration": {}}))

      assert {:error, {:corrupt_entry, "urn:wotex:lab:corrupt:1"}} =
               SqliteRepository.fetch(repository, "urn:wotex:lab:corrupt:1", nil)

      overwrite(
        connection,
        "urn:wotex:lab:corrupt:1",
        JSON.encode!(%{
          "thingDescription" => ThingDescription.to_map(thing("urn:wotex:lab:corrupt:1")),
          "registration" => %{"created" => "not-a-time", "modified" => "not-a-time"}
        })
      )

      {:ok, query} = Query.new([limit: 2], [])

      assert {:error, {:corrupt_entry, "urn:wotex:lab:corrupt:1"}} =
               SqliteRepository.list(repository, query, nil, @start, nil)

      overwrite(
        connection,
        "urn:wotex:lab:corrupt:1",
        ~s({"thingDescription": {}, "registration": 5})
      )

      assert {:error, {:corrupt_entry, "urn:wotex:lab:corrupt:1"}} =
               SqliteRepository.fetch(repository, "urn:wotex:lab:corrupt:1", nil)
    end
  end

  describe "sqlite store data directory" do
    @describetag :tmp_dir

    test "the instance data directory and file name are explicit" do
      assert {:error, :invalid_data_directory} = SqliteRepository.start_link([])
      assert {:error, :invalid_data_directory} = SqliteRepository.start_link(path: "")

      assert {:error, :invalid_data_directory} =
               SqliteRepository.start_link(path: "store", database: "../escape.sqlite3")
    end

    test "an unusable database file stops the owner with a structured reason", %{
      tmp_dir: tmp_dir
    } do
      Process.flag(:trap_exit, true)
      path = Path.join(tmp_dir, "blocked")
      File.mkdir_p!(Path.join(path, "directory.sqlite3"))

      assert {:error, {:sqlite, _}} = SqliteRepository.start_link(path: path)
    end

    test "retain false removes the database file when the owner terminates", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "disposable")
      {:ok, store} = SqliteRepository.start_link(path: path, retain: false, database: "d.sqlite3")
      file = SqliteRepository.database_path(store)

      assert file == Path.join(path, "d.sqlite3")
      assert File.exists?(file)
      assert :ok = GenServer.stop(store)

      refute File.exists?(file)
      refute File.exists?(file <> "-wal")
      refute File.exists?(file <> "-shm")
    end
  end

  describe "explicit port state" do
    test "ports reject invalid state explicitly" do
      assert {:error, :invalid_clock} = Clock.now(:wall)
      assert {:ok, @start} = Clock.now({:fixed, @start})
      assert {:error, :invalid_identifier_state} = Identifier.generate(:counter)
      assert :deny = Authorization.authorize(%{}, :nobody, :get, :collection, nil)
    end
  end

  defp start_directory(context) do
    lab = start_supervised!({Lab, id: "directory", max_children: 8})
    {module, repository} = start_store(context.store, lab, context.tmp_dir)
    {:ok, clock} = Clock.start_link(@start)
    {:ok, identifier} = Identifier.start_link()

    {:ok, service} =
      Service.new(
        repository: {module, repository},
        authorization: {Authorization, :allow_all},
        clock: {Clock, {:agent, clock}},
        identifier: {Identifier, identifier},
        introduction: thing("urn:wotex:lab:directory"),
        default_page_limit: 2,
        max_page_limit: 4,
        default_expiry_batch_limit: 2,
        max_expiry_batch_limit: 4
      )

    %{
      lab: lab,
      module: module,
      repository: repository,
      clock: clock,
      service: service,
      context: Context.new!(:operator, repository: {:tenant, "room-1"})
    }
  end

  defp start_store(:ets, lab, _) do
    {:ok, repository} = Lab.start_child(lab, :things, {EtsRepository, id: :store})
    {EtsRepository, repository}
  end

  defp start_store(:sqlite, lab, tmp_dir) do
    {:ok, repository} =
      Lab.start_child(lab, :things, {SqliteRepository, id: :store, path: tmp_dir})

    {SqliteRepository, repository}
  end

  defp start_named(EtsRepository, name, _), do: EtsRepository.start_link(name: name)

  defp start_named(SqliteRepository, name, tmp_dir),
    do: SqliteRepository.start_link(name: name, path: Path.join(tmp_dir, "named"))

  defp scoped_service(module, repository, clock, identifier, policy) do
    {:ok, service} =
      Service.new(
        repository: {module, repository},
        authorization: {Authorization, policy},
        clock: {Clock, {:agent, clock}},
        identifier: {Identifier, identifier},
        introduction: thing("urn:wotex:lab:directory")
      )

    service
  end

  defp open_database(repository) do
    {:ok, connection} = Sqlite3.open(SqliteRepository.database_path(repository))
    on_exit(fn -> Sqlite3.close(connection) end)
    connection
  end

  defp inject_abort(connection, event) do
    :ok =
      Sqlite3.execute(
        connection,
        "CREATE TRIGGER abort_#{event} BEFORE #{event} ON entries " <>
          "BEGIN SELECT RAISE(ABORT, 'injected'); END"
      )
  end

  defp overwrite(connection, identifier, document) do
    {:ok, statement} =
      Sqlite3.prepare(connection, "UPDATE entries SET document = ?2 WHERE identifier = ?1")

    :ok = Sqlite3.bind(statement, [identifier, {:blob, document}])
    :done = Sqlite3.step(connection, statement)
    :ok = Sqlite3.release(connection, statement)
  end

  defp thing(identifier, extra \\ %{}) do
    base = %{
      "@context" => Wotex.td_context_1_1(),
      "title" => "Lab Thing",
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
    }

    base = if identifier, do: Map.put(base, "id", identifier), else: base

    base =
      if Map.has_key?(extra, "registration"),
        do:
          Map.put(base, "@context", [
            Wotex.td_context_1_1(),
            "https://www.w3.org/2022/wot/discovery"
          ]),
        else: base

    {:ok, td} = ThingDescription.from_map(Map.merge(base, extra))
    td
  end
end
