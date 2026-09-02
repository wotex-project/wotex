defmodule Wotex.DirectoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Directory
  alias Wotex.Directory.{Entry, Error, Fixtures, MemoryRepository, Page, Query}
  alias Wotex.Directory.{Registration, TestService, ThingDescriptions}

  @now ~U[2026-09-02 10:00:00Z]
  @discovery_context "https://www.w3.org/2022/wot/discovery"

  describe "registration" do
    test "creates and then replaces a named registration with explicit outcomes" do
      setup = TestService.build()
      thing_description = Fixtures.thing_description("urn:example:thing:1")

      assert {:ok, created} =
               Directory.register(setup.service, thing_description, setup.context)

      assert created.operation == :register
      assert created.status == :created
      assert created.entry.identifier == "urn:example:thing:1"
      assert created.entry.version == 1
      assert created.entry.registration.created == @now

      changed = Fixtures.thing_description("urn:example:thing:1", %{"title" => "Changed Thing"})

      assert {:ok, replaced} = Directory.register(setup.service, changed, setup.context)
      assert replaced.status == :replaced
      assert replaced.entry.version == 2
      assert replaced.entry.registration.created == created.entry.registration.created

      assert Wotex.ThingDescription.to_map(replaced.entry.thing_description)["title"] ==
               "Changed Thing"

      assert_receive {:authorize, :principal, :register, :collection, :authorization_context}
      assert_receive {:authorize, :principal, :register, :collection, :authorization_context}

      assert_receive {:authorize, :principal, :register, {:entry, "urn:example:thing:1"},
                      :authorization_context}

      assert_receive {:authorize, :principal, :register, {:entry, "urn:example:thing:1"},
                      :authorization_context}

      assert [
               {:fetch, "urn:example:thing:1", :repository_context},
               {:insert, "urn:example:thing:1", :repository_context},
               {:fetch, "urn:example:thing:1", :repository_context},
               {:replace, "urn:example:thing:1", 1, :repository_context}
             ] = MemoryRepository.calls(setup.repository)
    end

    test "assigns an identifier to an anonymous Thing Description before insert" do
      setup =
        TestService.build(identifiers: ["urn:uuid:11111111-1111-4111-8111-111111111111"])

      anonymous = Fixtures.thing_description(nil)

      assert {:ok, mutation} = Directory.register(setup.service, anonymous, setup.context)
      assert mutation.status == :created
      assert mutation.entry.identifier == "urn:uuid:11111111-1111-4111-8111-111111111111"
      assert ThingDescriptions.id(mutation.entry.thing_description) == mutation.entry.identifier
    end

    test "owns Discovery registration input and emits an enriched Thing Description" do
      setup = TestService.build()

      enriched =
        Fixtures.thing_description("urn:example:thing:1", %{
          "@context" => [Wotex.td_context_1_1(), @discovery_context],
          "registration" => %{"ttl" => 60, "x-example:source" => "test"}
        })

      assert {:ok, mutation} = Directory.register(setup.service, enriched, setup.context)
      assert mutation.entry.registration.ttl == 60
      assert mutation.entry.registration.expires == DateTime.add(@now, 60, :second)

      assert {:ok, returned} = Entry.enriched_thing_description(mutation.entry)
      returned_map = Wotex.ThingDescription.to_map(returned)
      assert @discovery_context in returned_map["@context"]
      assert returned_map["registration"]["created"] == "2026-09-02T10:00:00Z"
      assert returned_map["registration"]["x-example:source"] == "test"
    end

    test "rejects registration metadata without the Discovery context" do
      setup = TestService.build()

      invalid =
        Fixtures.thing_description("urn:example:thing:1", %{
          "registration" => %{"ttl" => 60}
        })

      assert {:error, %Error{code: :invalid_thing_description}} =
               Directory.register(setup.service, invalid, setup.context)

      assert MemoryRepository.entries(setup.repository) == %{}
    end

    test "reports identifier port failure and collision without retrying" do
      invalid_setup = TestService.build(identifiers: ["relative-identifier"])
      anonymous = Fixtures.thing_description(nil)

      assert {:error, %Error{code: :identifier_failure}} =
               Directory.register(invalid_setup.service, anonymous, invalid_setup.context)

      first = TestService.build(identifiers: ["urn:example:collision"])
      existing = Fixtures.thing_description("urn:example:collision")
      assert {:ok, _mutation} = Directory.register(first.service, existing, first.context)

      anonymous_service = %{
        first.service
        | identifier: {Wotex.Directory.TestIdentifier, first.identifier}
      }

      assert {:error, %Error{code: :conflict}} =
               Directory.register(anonymous_service, anonymous, first.context)
    end
  end

  describe "authorization and retrieval" do
    test "denial occurs before repository access and does not disclose existence" do
      setup = TestService.build(authorization: %{test_pid: self(), result: :deny})

      assert {:error, %Error{code: :forbidden, identifier: "urn:example:thing:1"}} =
               Directory.get(setup.service, "urn:example:thing:1", setup.context)

      assert_receive {:authorize, :principal, :get, {:entry, "urn:example:thing:1"},
                      :authorization_context}

      assert MemoryRepository.calls(setup.repository) == []
    end

    test "named register authorizes its target before checking existence" do
      identifier = "urn:example:thing:1"

      authorization = %{
        test_pid: self(),
        result: :ok,
        results: %{{:register, {:entry, identifier}} => :deny}
      }

      setup = TestService.build(authorization: authorization)

      assert {:error, %Error{code: :forbidden, identifier: ^identifier}} =
               Directory.register(
                 setup.service,
                 Fixtures.thing_description(identifier),
                 setup.context
               )

      assert MemoryRepository.calls(setup.repository) == []
    end

    test "retrieval assigns returned metadata without mutating storage" do
      entry = entry("urn:example:thing:1")
      setup = TestService.build(entries: [entry])

      assert {:ok, returned} =
               Directory.get(setup.service, "urn:example:thing:1", setup.context)

      assert returned.registration.retrieved == @now

      assert MemoryRepository.entries(setup.repository)[entry.identifier].registration.retrieved ==
               nil
    end

    test "expired and missing entries have distinct deterministic results" do
      expired = entry("urn:example:expired", expires: DateTime.add(@now, -1, :second))
      setup = TestService.build(entries: [expired])

      assert {:error, %Error{code: :expired}} =
               Directory.get(setup.service, expired.identifier, setup.context)

      assert {:error, %Error{code: :not_found}} =
               Directory.get(setup.service, "urn:example:missing", setup.context)
    end
  end

  describe "replacement and patch" do
    test "replacement validates identifier and optimistic version" do
      existing = entry("urn:example:thing:1")
      setup = TestService.build(entries: [existing])
      changed = Fixtures.thing_description(existing.identifier, %{"title" => "Replacement"})

      assert {:ok, mutation} =
               Directory.replace(
                 setup.service,
                 existing.identifier,
                 changed,
                 setup.context,
                 if_version: 1
               )

      assert mutation.status == :replaced
      assert mutation.entry.version == 2

      assert {:error, %Error{code: :conflict}} =
               Directory.replace(
                 setup.service,
                 existing.identifier,
                 changed,
                 setup.context,
                 if_version: 1
               )

      mismatch = Fixtures.thing_description("urn:example:other")

      assert {:error, %Error{code: :identifier_mismatch}} =
               Directory.replace(
                 setup.service,
                 existing.identifier,
                 mismatch,
                 setup.context
               )
    end

    test "patch merges and core-validates before conditional persistence" do
      existing = entry("urn:example:thing:1")
      setup = TestService.build(entries: [existing])

      patch = %{
        "title" => "Patched Thing",
        "properties" => %{"temperature" => %{"maximum" => 120}}
      }

      assert {:ok, mutation} =
               Directory.patch(setup.service, existing.identifier, patch, setup.context)

      map = Wotex.ThingDescription.to_map(mutation.entry.thing_description)
      assert map["title"] == "Patched Thing"
      assert map["properties"]["temperature"]["maximum"] == 120
      assert mutation.entry.version == 2
    end

    test "invalid patch leaves the stored entry unchanged" do
      existing = entry("urn:example:thing:1")
      setup = TestService.build(entries: [existing])

      assert {:error, %Error{code: :invalid_thing_description}} =
               Directory.patch(
                 setup.service,
                 existing.identifier,
                 %{"title" => nil},
                 setup.context
               )

      assert MemoryRepository.entries(setup.repository)[existing.identifier] == existing
      refute Enum.any?(MemoryRepository.calls(setup.repository), &match?({:replace, _, _, _}, &1))
    end

    test "patch cannot assign or remove server registration fields" do
      existing = entry("urn:example:thing:1")
      setup = TestService.build(entries: [existing])

      for patch <- [
            %{"registration" => %{"created" => "2030-01-01T00:00:00Z"}},
            %{"registration" => %{"modified" => nil}},
            %{"registration" => nil}
          ] do
        assert {:error, %Error{code: :invalid_request}} =
                 Directory.patch(
                   setup.service,
                   existing.identifier,
                   patch,
                   setup.context
                 )
      end

      assert MemoryRepository.entries(setup.repository)[existing.identifier] == existing
    end

    test "empty patch refreshes a relative expiry" do
      registration = registration(DateTime.add(@now, -30, :second), ttl: 60)
      existing = entry("urn:example:thing:1", registration: registration)
      setup = TestService.build(entries: [existing])

      assert {:ok, mutation} =
               Directory.patch(setup.service, existing.identifier, %{}, setup.context)

      assert mutation.entry.registration.expires == DateTime.add(@now, 60, :second)
      assert mutation.entry.registration.modified == @now
    end
  end

  describe "deletion" do
    test "deletes only the observed version and returns the removed entry" do
      existing = entry("urn:example:thing:1")
      setup = TestService.build(entries: [existing])

      assert {:ok, mutation} =
               Directory.delete(
                 setup.service,
                 existing.identifier,
                 setup.context,
                 if_version: 1
               )

      assert mutation.status == :deleted
      assert mutation.entry == existing
      assert MemoryRepository.entries(setup.repository) == %{}
    end
  end

  describe "listing and query" do
    test "returns bounded ordered pages tied to one collection revision" do
      entries = [
        entry("urn:example:thing:c"),
        entry("urn:example:thing:a"),
        entry("urn:example:thing:b")
      ]

      setup = TestService.build(entries: entries, revision: 7)

      assert {:ok, first} = Directory.list(setup.service, setup.context)

      assert Enum.map(first.entries, & &1.identifier) == [
               "urn:example:thing:a",
               "urn:example:thing:b"
             ]

      assert Enum.all?(first.entries, &(&1.registration.retrieved == @now))
      assert is_binary(first.collection_revision)
      refute first.collection_revision == ""
      assert first.next_offset == 2

      first_query = %Query{profile: :listing, offset: 0, limit: 2, format: :array}
      next_query = Page.next_query(first, first_query)

      assert {:ok, second} = Directory.query(setup.service, next_query, setup.context)
      assert Enum.map(second.entries, & &1.identifier) == ["urn:example:thing:c"]
      assert second.next_offset == nil
      assert second.collection_revision == first.collection_revision
    end

    test "detects a collection change between pages" do
      setup =
        TestService.build(entries: [entry("urn:example:a"), entry("urn:example:b")], revision: 2)

      assert {:ok, first} = Directory.list(setup.service, setup.context, limit: 1)
      query = %Query{profile: :listing, offset: 0, limit: 1, format: :array}
      next_query = Page.next_query(first, query)

      assert {:ok, _mutation} =
               Directory.register(
                 setup.service,
                 Fixtures.thing_description("urn:example:c"),
                 setup.context
               )

      assert {:error, %Error{code: :collection_changed}} =
               Directory.query(setup.service, next_query, setup.context)
    end

    test "detects wall-clock expiry that changes active membership between pages" do
      crossing = entry("urn:example:a", expires: DateTime.add(@now, 1, :second))
      stable = entry("urn:example:b", expires: DateTime.add(@now, 60, :second))
      setup = TestService.build(entries: [crossing, stable], revision: 2)

      assert {:ok, first} = Directory.list(setup.service, setup.context, limit: 1)
      query = %Query{profile: :listing, offset: 0, limit: 1, format: :array}
      next_query = Page.next_query(first, query)

      later_service = %{
        setup.service
        | clock: {Wotex.Directory.TestClock, DateTime.add(@now, 2, :second)}
      }

      assert {:error, %Error{code: :collection_changed}} =
               Directory.query(later_service, next_query, setup.context)

      assert MemoryRepository.snapshot(setup.repository).revision == 2
    end

    test "rejects unsupported profiles and excessive limits explicitly" do
      setup = TestService.build()

      unsupported = %Query{
        profile: :sparql,
        offset: 0,
        limit: 1,
        format: :array
      }

      assert {:error, %Error{code: :unsupported_query_profile}} =
               Directory.query(setup.service, unsupported, setup.context)

      assert {:error, %Error{code: :invalid_request}} =
               Directory.list(setup.service, setup.context, limit: 5)
    end
  end

  describe "expiry and Introduction" do
    test "purges only a bounded sorted set of due entries" do
      entries = [
        entry("urn:example:expired:b", expires: DateTime.add(@now, -1, :second)),
        entry("urn:example:future", expires: DateTime.add(@now, 60, :second)),
        entry("urn:example:expired:a", expires: @now)
      ]

      setup = TestService.build(entries: entries)

      assert {:ok, expiry} = Directory.expire(setup.service, setup.context, limit: 2)
      assert expiry.strategy == :purge

      assert Enum.map(expiry.entries, & &1.identifier) == [
               "urn:example:expired:a",
               "urn:example:expired:b"
             ]

      assert Map.keys(MemoryRepository.entries(setup.repository)) == ["urn:example:future"]
    end

    test "retains an explicit expired state when selected" do
      due = entry("urn:example:expired", expires: @now)
      setup = TestService.build(entries: [due], expiry_strategy: :retain)

      assert {:ok, expiry} = Directory.expire(setup.service, setup.context)
      assert [%Entry{state: :expired, version: 2}] = expiry.entries
      assert MemoryRepository.entries(setup.repository)[due.identifier].state == :expired
    end

    test "retain processes a due active entry only once" do
      due = entry("urn:example:expired", expires: @now)
      setup = TestService.build(entries: [due], expiry_strategy: :retain, revision: 4)

      assert {:ok, first} = Directory.expire(setup.service, setup.context)
      assert [%Entry{state: :expired, version: 2}] = first.entries
      assert MemoryRepository.snapshot(setup.repository).revision == 5

      assert {:ok, second} = Directory.expire(setup.service, setup.context)
      assert second.entries == []
      assert MemoryRepository.snapshot(setup.repository).revision == 5
      assert MemoryRepository.entries(setup.repository)[due.identifier].version == 2
    end

    test "purge removes due active and retained expired entries in one bounded batch" do
      active = entry("urn:example:expired:b", expires: @now)
      retained = entry("urn:example:expired:a", expires: @now, state: :expired, version: 2)
      future = entry("urn:example:future", expires: DateTime.add(@now, 60, :second))
      setup = TestService.build(entries: [active, retained, future], revision: 8)

      assert {:ok, expiry} = Directory.expire(setup.service, setup.context, limit: 2)

      assert Enum.map(expiry.entries, &{&1.identifier, &1.state}) == [
               {"urn:example:expired:a", :expired},
               {"urn:example:expired:b", :active}
             ]

      assert Map.keys(MemoryRepository.entries(setup.repository)) == ["urn:example:future"]
      assert MemoryRepository.snapshot(setup.repository).revision == 9
    end

    test "an expiry batch with no due entries does not advance collection revision" do
      future = entry("urn:example:future", expires: DateTime.add(@now, 60, :second))
      setup = TestService.build(entries: [future], revision: 11)

      assert {:ok, expiry} = Directory.expire(setup.service, setup.context)
      assert expiry.entries == []
      assert MemoryRepository.snapshot(setup.repository).revision == 11
    end

    test "Introduction bypasses all consumer ports and contains no entry" do
      setup = TestService.build()

      assert {:ok, introduction} = Directory.introduction(setup.service)
      assert introduction.path == "/.well-known/wot"
      assert introduction.media_type == "application/td+json"
      assert Wotex.ThingDescription.id(introduction.thing_description) == "urn:example:directory"
      assert MemoryRepository.calls(setup.repository) == []
      refute_received {:authorize, _, _, _, _}
    end
  end

  describe "port failures" do
    test "redacts authorization, clock, and repository adapter reasons" do
      denied = TestService.build(authorization: %{result: {:error, {:secret, "value"}}})

      assert {:error, %Error{code: :authorization_failure, details: %{}} = authorization_error} =
               Directory.list(denied.service, denied.context)

      refute String.contains?(authorization_error.message, "secret")

      clock_failure = TestService.build(now: {:error, {:secret, "value"}})

      assert {:error, %Error{code: :clock_failure, details: %{}} = clock_error} =
               Directory.list(clock_failure.service, clock_failure.context)

      refute String.contains?(clock_error.message, "secret")

      repository_failure = TestService.build()

      service = %{
        repository_failure.service
        | repository: {Wotex.Directory.FailureRepository, nil}
      }

      assert {:error, %Error{code: :repository_failure, details: %{}} = repository_error} =
               Directory.get(service, "urn:example:thing:1", repository_failure.context)

      refute String.contains?(repository_error.message, "unavailable")
    end
  end

  defp entry(identifier, options \\ []) do
    registration =
      Keyword.get_lazy(options, :registration, fn ->
        registration(@now, expires: Keyword.get(options, :expires))
      end)

    {:ok, entry} =
      Entry.new(identifier, Fixtures.thing_description(identifier), registration,
        version: Keyword.get(options, :version, 1),
        state: Keyword.get(options, :state, :active)
      )

    entry
  end

  defp registration(created, options) do
    raw =
      %{}
      |> maybe_put("expires", Keyword.get(options, :expires))
      |> maybe_put("ttl", Keyword.get(options, :ttl))

    {:ok, registration} = Registration.create(created, {:present, raw}, :register)
    registration
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
