defmodule Wotex.Lab.DirectoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory
  alias Wotex.Directory.{Context, Error, Event, Expiry, Mutation, Page, Service}
  alias Wotex.Lab
  alias Wotex.Lab.Adapters.Directory.{Authorization, Clock, EtsRepository, Identifier}
  alias Wotex.ThingDescription

  @start ~U[2026-09-07 12:00:00Z]

  setup do
    lab = start_supervised!({Lab, id: "directory", max_children: 8})
    {:ok, repository} = Lab.start_child(lab, :things, {EtsRepository, id: :store})
    {:ok, clock} = Clock.start_link(@start)
    {:ok, identifier} = Identifier.start_link()

    {:ok, service} =
      Service.new(
        repository: {EtsRepository, repository},
        authorization: {Authorization, :allow_all},
        clock: {Clock, {:agent, clock}},
        identifier: {Identifier, identifier},
        introduction: thing("urn:wotex:lab:directory"),
        default_page_limit: 2,
        max_page_limit: 4,
        default_expiry_batch_limit: 2,
        max_expiry_batch_limit: 4
      )

    context = Context.new!(:operator, repository: {:tenant, "room-1"})
    %{lab: lab, repository: repository, clock: clock, service: service, context: context}
  end

  test "register, get, replace, patch, delete and events work through the public ports", %{
    service: service,
    context: context,
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
             Directory.patch(service, "urn:wotex:lab:room:1", %{"title" => "Patched"}, context)

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
             EtsRepository.stats(repository)

    assert calls.insert == 2 and calls.delete == 1 and calls.replace == 2
    assert {:ok, introduction} = Directory.introduction(service)
    assert introduction.thing_description == thing("urn:wotex:lab:directory")
  end

  test "authorization runs before any repository access and separates principals", %{
    repository: repository,
    clock: clock
  } do
    policy = %{
      reader: [:get, :list],
      writer: {:tenant, "room-1", [:register, :get, :replace, :patch, :delete, :list, :expire]}
    }

    {:ok, identifier} = Identifier.start_link()

    {:ok, service} =
      Service.new(
        repository: {EtsRepository, repository},
        authorization: {Authorization, policy},
        clock: {Clock, {:agent, clock}},
        identifier: {Identifier, identifier},
        introduction: thing("urn:wotex:lab:directory")
      )

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

    assert %{calls: calls} = EtsRepository.stats(repository)
    refute Map.has_key?(calls, :insert)

    assert {:ok, _mutation} = Directory.register(service, thing("urn:x:1"), writer)
    assert {:ok, _entry} = Directory.get(service, "urn:x:1", reader)
    assert {:error, %Error{code: :forbidden}} = Directory.delete(service, "urn:x:1", reader)

    {:ok, broken} =
      Service.new(
        repository: {EtsRepository, repository},
        authorization: {Authorization, :not_a_policy},
        clock: {Clock, {:agent, clock}},
        identifier: {Identifier, identifier},
        introduction: thing("urn:wotex:lab:directory")
      )

    assert {:error, %Error{phase: :authorization}} = Directory.get(broken, "urn:x:1", reader)
  end

  test "competing conditional writes have exactly one winner", %{service: service, context: context} do
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

    assert {:ok, _deleted} =
             Directory.delete(service, "urn:wotex:lab:race:1", context, if_version: 2)
  end

  test "listing pages by keyset in stable order and survives expiry drift but not mutation", %{
    service: service,
    context: context,
    clock: clock
  } do
    for suffix <- ["c", "a", "e", "b", "d"] do
      ttl = if suffix == "b", do: %{"registration" => %{"ttl" => 30}}, else: %{}

      {:ok, _mutation} =
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
    {:ok, _mutation} = Directory.register(service, thing("urn:wotex:lab:list:f"), context)

    assert {:error, %Error{code: :collection_changed}} =
             Directory.list(service, context, cursor: stale)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.list(service, context, cursor: "bogus")

    assert {:error, %Error{code: :invalid_request}} = Directory.list(service, context, limit: 99)
  end

  test "expiry is bounded, repeatable, and honors purge and retain", %{
    service: service,
    context: context,
    clock: clock,
    repository: repository
  } do
    for n <- 1..5 do
      {:ok, _mutation} =
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

    assert Enum.map([one, two], & &1.identifier) == ["urn:wotex:lab:ttl:1", "urn:wotex:lab:ttl:2"]
    assert {:ok, %Expiry{entries: [three]}} = Directory.expire(service, context, limit: 4)
    assert three.identifier == "urn:wotex:lab:ttl:3"
    assert {:ok, %Expiry{entries: []}} = Directory.expire(service, context)
    assert %{size: 2} = EtsRepository.stats(repository)

    Clock.advance(clock, 100)

    assert {:ok, %Expiry{strategy: :retain, entries: [four, five]}} =
             Directory.expire(service, context, strategy: :retain)

    assert Enum.all?([four, five], &(&1.state == :expired and &1.version == 2))
    assert {:ok, %Expiry{entries: []}} = Directory.expire(service, context, strategy: :retain)
    assert {:error, %Error{code: :expired}} = Directory.get(service, four.identifier, context)
    assert %{size: 2} = EtsRepository.stats(repository)
    assert {:ok, %Expiry{entries: [_a, _b]}} = Directory.expire(service, context, strategy: :purge)
    assert %{size: 0} = EtsRepository.stats(repository)
  end

  test "the ETS store is volatile: a restarted owner starts empty with a fresh revision", %{
    lab: lab,
    service: service,
    context: context,
    repository: repository
  } do
    {:ok, _mutation} = Directory.register(service, thing("urn:wotex:lab:volatile:1"), context)
    assert %{revision: "ets:1"} = EtsRepository.stats(repository)

    monitor = Process.monitor(repository)
    Process.exit(repository, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^repository, :killed}

    {:ok, replacement} = Lab.start_child(lab, :things, {EtsRepository, id: :replacement})
    assert %{revision: "ets:0", size: 0} = EtsRepository.stats(replacement)
    assert {:ok, [_directory, _store]} = {:ok, Enum.take(Supervisor.which_children(lab), 2)}
  end

  test "ports reject invalid state explicitly" do
    assert {:error, :invalid_clock} = Clock.now(:wall)
    assert {:ok, @start} = Clock.now({:fixed, @start})
    assert {:error, :invalid_identifier_state} = Identifier.generate(:counter)
    assert :deny = Authorization.authorize(%{}, :nobody, :get, :collection, nil)
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

  test "the repository callbacks report absence, conflict and collisions directly", %{
    repository: repository,
    service: service,
    context: context
  } do
    name = {:global, {:ets_store, make_ref()}}
    {:ok, named} = EtsRepository.start_link(name: name)
    assert GenServer.whereis(name) == named

    {:ok, %Mutation{entry: entry}} =
      Directory.register(service, thing("urn:wotex:lab:direct:1"), context)

    assert :not_found = EtsRepository.fetch(repository, "urn:none", nil)

    assert {:error, :not_found} =
             EtsRepository.replace(repository, %{entry | identifier: "urn:none"}, 1, nil)

    assert {:error, :not_found} = EtsRepository.delete(repository, "urn:none", 1, nil)
    assert {:error, :already_exists} = EtsRepository.insert(repository, entry, nil)
    assert {:error, :conflict} = EtsRepository.replace(repository, entry, 2, nil)
    assert {:error, :conflict} = EtsRepository.delete(repository, entry.identifier, 2, nil)
    assert :ok = EtsRepository.delete(repository, entry.identifier, 1, nil)
  end
end
