defmodule Wotex.Directory.ReferenceConsumerContract do
  @moduledoc false

  import ExUnit.Assertions

  alias Wotex.Directory
  alias Wotex.Directory.{Context, Error, Event, Page, Query, RepositoryProbe, Service}
  alias Wotex.Directory.{ReferenceAuthorization, ReferenceClock, ReferenceIdentifier}
  alias Wotex.ThingDescription

  @now ~U[2026-09-02 10:00:00Z]
  @id "urn:example:reference:1"

  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(_) do
    tests =
      for scenario <- [:lifecycle, :isolation, :time_and_pages, :failed_ports, :authority] do
        quote do
          test unquote("reference consumer: #{scenario}"), %{repository_fixture: fixture} do
            Wotex.Directory.ReferenceConsumerContract.verify(unquote(scenario), fixture)
          end
        end
      end

    quote do
      (unquote_splicing(tests))
    end
  end

  @spec verify(atom(), map()) :: term()
  def verify(:lifecycle, fixture) do
    service = service(fixture)
    context = context(fixture.scope)

    assert {:ok, created} =
             Directory.register(service, thing_description(nil), context,
               registration: %{
                 "ttl" => 10,
                 "expires" => DateTime.to_iso8601(DateTime.add(@now, 999)),
                 "urn:example:registration" => "preserved"
               }
             )

    assert created.status == :created
    assert created.entry.identifier == @id
    assert created.entry.version == 1
    assert created.entry.registration.expires == DateTime.add(@now, 10)
    assert {:ok, event} = Event.from_mutation(created)
    assert event.type == :thing_created
    assert event.data["urn:example:extension"] == %{"preserved" => true}
    assert event.data["registration"]["urn:example:registration"] == "preserved"
    assert "https://www.w3.org/2022/wot/discovery" in event.data["@context"]
    assert {:ok, retrieved} = Directory.get(service, @id, context)
    assert retrieved.registration.retrieved == @now
    assert fetch(fixture, @id).registration.retrieved == nil

    later = at(service, 1)

    assert {:ok, replaced} =
             Directory.replace(later, @id, thing_description(@id, "Replaced"), context,
               if_version: 1
             )

    assert replaced.entry.version == 2
    assert replaced.entry.registration.created == @now
    assert replaced.entry.registration.modified == DateTime.add(@now, 1)
    assert replaced.entry.registration.expires == DateTime.add(@now, 11)
    assert_updated(replaced)

    assert {:error, %Error{code: :invalid_thing_description}} =
             Directory.patch(later, @id, %{"title" => nil}, context)

    assert fetch(fixture, @id) == replaced.entry

    for field <- ~w(created modified retrieved) do
      assert {:error, %Error{code: :invalid_request}} =
               Directory.patch(later, @id, %{"registration" => %{field => nil}}, context)

      assert fetch(fixture, @id) == replaced.entry
    end

    assert {:error, %Error{code: :identifier_mismatch}} =
             Directory.replace(later, @id, thing_description("urn:example:other"), context)

    assert {:ok, patched} =
             Directory.patch(
               later,
               @id,
               %{"urn:example:extension" => %{"added" => [1, 2]}},
               context,
               if_version: 2
             )

    assert patched.entry.version == 3
    assert_updated(patched)

    assert ThingDescription.to_map(patched.entry.thing_description)["urn:example:extension"] ==
             %{"preserved" => true, "added" => [1, 2]}

    assert {:ok, named} = Directory.register(later, thing_description(@id, "Named"), context)
    assert named.status == :replaced
    assert named.entry.version == 4
    assert_updated(named)
    assert {:ok, page} = Directory.list(later, context)
    assert identifiers(page) == [@id]

    assert {:error, %Error{code: :conflict}} =
             Directory.delete(later, @id, context, if_version: 3)

    assert {:ok, deleted} = Directory.delete(later, @id, context, if_version: 4)

    assert {:ok, %Event{type: :thing_deleted, data: %{"id" => @id}}} =
             Event.from_mutation(deleted)

    assert {:error, %Error{code: :not_found}} = Directory.get(later, @id, context)
    assert {:ok, another} = Directory.register(service, thing_description(nil), context)
    assert another.entry.identifier == "urn:example:reference:2"
  end

  def verify(:isolation, fixture) do
    service = service(fixture)
    first = context(fixture.scope)
    second = context(fixture.other_scope)
    assert {:ok, _} = Directory.register(service, thing_description(@id, "First"), first)
    assert {:ok, _} = Directory.register(service, thing_description(@id, "Second"), second)
    assert {:ok, first_entry} = Directory.get(service, @id, first)
    assert {:ok, second_entry} = Directory.get(service, @id, second)
    assert ThingDescription.to_map(first_entry.thing_description)["title"] == "First"
    assert ThingDescription.to_map(second_entry.thing_description)["title"] == "Second"
    assert {:ok, _} = Directory.delete(service, @id, first)
    assert {:ok, _} = Directory.get(service, @id, second)
    drain()

    denied =
      Context.new!(:unauthorized, authorization: :reference_policy, repository: fixture.scope)

    assert {:error, missing} = Directory.get(service, @id, denied)

    assert {:error, present} =
             Directory.get(service, @id, %{denied | repository: fixture.other_scope})

    assert missing == present
    assert missing.code == :forbidden
    assert {:error, %Error{code: :forbidden}} = Directory.list(service, denied)
    assert {:error, %Error{code: :forbidden}} = Directory.expire(service, denied)
    refute_received {:repository_callback, _, _}
    refute_received {:reference_port, :now, _, _}
    drain()

    assert {:ok, _} = Directory.get(service, @id, second)
    caller = self()
    scope = fixture.other_scope

    assert_receive {:reference_port, :authorize, ^caller,
                    [:reference_principal, :get, {:entry, @id}, :reference_policy]}

    assert_receive {:repository_callback, :fetch, [@id, ^scope]}
    assert_receive {:reference_port, :now, ^caller, []}
  end

  def verify(:time_and_pages, fixture) do
    service = service(fixture)
    context = context(fixture.scope)
    ids = ~w(urn:example:a urn:example:b urn:example:é)

    for {id, registration} <- Enum.zip(ids, [%{"ttl" => 1}, %{"ttl" => 2}, %{}]) do
      assert {:ok, _} =
               Directory.register(service, thing_description(id), context,
                 registration: registration
               )
    end

    assert {:ok, query} = Query.new(limit: 1, format: :collection)
    assert {:ok, first} = Directory.query(service, query, context)
    assert identifiers(first) == ["urn:example:a"]
    continuation = Page.next_query(first, query)
    assert continuation.limit == 1
    assert continuation.format == :collection
    later = at(service, 1)
    assert {:ok, second} = Directory.query(later, continuation, context)
    assert identifiers(second) == ["urn:example:b"]
    assert second.collection_revision == first.collection_revision
    assert hd(second.entries).registration.retrieved == DateTime.add(@now, 1)
    assert {:error, %Error{code: :expired}} = Directory.get(later, "urn:example:a", context)
    assert {:ok, _} = Directory.get(service, "urn:example:a", context)
    assert fetch(fixture, "urn:example:a").state == :active

    assert {:ok, retained} = Directory.expire(later, context, strategy: :retain, limit: 1)
    assert [%{identifier: "urn:example:a", state: :expired, version: 2}] = retained.entries

    assert {:error, %Error{code: :collection_changed}} =
             Directory.query(later, continuation, context)

    assert {:ok, after_retain} = Directory.list(later, context)
    assert {:ok, %{entries: []}} = Directory.expire(later, context, strategy: :retain)
    assert {:ok, repeated} = Directory.list(later, context)
    assert repeated.collection_revision == after_retain.collection_revision
    assert {:ok, purged} = Directory.expire(later, context)
    assert Enum.map(purged.entries, & &1.identifier) == ["urn:example:a"]
    assert {:error, %Error{code: :not_found}} = Directory.get(service, "urn:example:a", context)
    assert {:ok, remaining} = Directory.list(at(service, 2), context)
    assert identifiers(remaining) == ["urn:example:é"]
    assert {:ok, _} = Directory.get(service, "urn:example:b", context)

    assert {:error, %Error{code: :clock_regression}} =
             Directory.patch(at(service, -1), "urn:example:b", %{"title" => "Earlier"}, context)

    drain()
    assert {:error, %Error{code: :invalid_request}} = Directory.list(service, context, limit: 0)

    assert {:error, %Error{code: :invalid_request}} =
             Directory.list(service, context, cursor: "not-a-cursor")

    for profile <- [:jsonpath, :xpath, :sparql] do
      assert {:error, %Error{code: :unsupported_query_profile}} =
               Directory.query(service, %{query | profile: profile}, context)
    end

    refute_received {:reference_port, _, _, _}
    refute_received {:repository_callback, _, _}
  end

  def verify(:failed_ports, fixture) do
    service = service(fixture)
    context = context(fixture.scope)
    secret = {:private_port_state, :reference_principal, "synthetic-sensitive-value"}

    cases = [
      {:authorization,
       {ReferenceAuthorization, %{observer: self(), policy: fn _ -> {:error, secret} end}},
       :authorization_failure},
      {:clock, {ReferenceClock, %{observer: self(), result: {:error, secret}}}, :clock_failure},
      {:identifier, {ReferenceIdentifier, %{observer: self(), next: fn -> {:error, secret} end}},
       :identifier_failure},
      {:identifier, {ReferenceIdentifier, %{observer: self(), next: fn -> {:ok, "relative"} end}},
       :identifier_failure}
    ]

    for {port, implementation, code} <- cases do
      assert {:error, error} =
               Directory.register(
                 Map.put(service, port, implementation),
                 thing_description(nil),
                 context
               )

      assert error.code == code
      assert error.details == %{operation: :register}
      refute inspect(error) =~ "synthetic-sensitive-value"
      refute_received {:repository_callback, _, _}
      drain()
    end

    collision =
      %{
        service
        | identifier: {ReferenceIdentifier, %{observer: self(), next: fn -> {:ok, @id} end}}
      }

    assert {:ok, created} = Directory.register(collision, thing_description(nil), context)
    drain()

    assert {:error, %Error{code: :conflict}} =
             Directory.register(collision, thing_description(nil), context)

    assert_receive {:reference_port, :generate, _, []}
    refute_received {:reference_port, :generate, _, []}
    assert_receive {:repository_callback, :insert, _}
    refute_received {:repository_callback, _, _}
    assert fetch(fixture, @id) == created.entry
    drain()

    faulty = %{
      service
      | repository:
          {RepositoryProbe,
           %{
             repository: fixture.repository,
             observer: self(),
             faults: %{replace: {:error, secret}}
           }}
    }

    assert {:error, error} = Directory.patch(faulty, @id, %{"title" => "Refused"}, context)
    assert error.code == :repository_failure
    assert error.details == %{operation: :patch, identifier: @id}
    refute inspect(error) =~ "synthetic-sensitive-value"
    assert_receive {:repository_callback, :fetch, _}
    assert_receive {:repository_callback, :replace, _}
    refute_received {:repository_callback, _, _}
    assert fetch(fixture, @id) == created.entry
  end

  def verify(:authority, fixture) do
    service = service(fixture)
    refute_received {:reference_port, _, _, _}
    refute_received {:repository_callback, _, _}
    assert {:ok, introduction} = Directory.introduction(service)
    assert introduction.path == "/.well-known/wot"
    assert introduction.media_type == "application/td+json"
    assert ThingDescription.id(introduction.thing_description) == "urn:example:directory"
    refute_received {:reference_port, _, _, _}
    refute_received {:repository_callback, _, _}

    assert {:ok, created} =
             Directory.register(service, thing_description(nil), context(fixture.scope))

    caller = self()
    assert_receive {:reference_port, :generate, ^caller, []}
    assert_receive {:reference_port, :now, ^caller, []}
    assert_receive {:reference_port, :authorize, ^caller, _}
    drain()
    assert {:ok, full} = Event.from_mutation(created)
    assert {:ok, minimum} = Event.from_mutation(created, payload: :identifier)
    assert minimum.data == %{"id" => @id}
    assert Enum.sort(Map.keys(Map.from_struct(full))) == [:data, :type]

    assert {:error, %Error{code: :invalid_request}} =
             Event.from_mutation(created, payload: :stream)

    refute_received {:reference_port, _, _, _}
    refute_received {:repository_callback, _, _}

    independent = service(fixture)

    assert {:ok, second} =
             Directory.register(independent, thing_description(nil), context(fixture.other_scope))

    assert second.entry.identifier == @id
    assert second.entry.version == 1
    assert fetch(fixture, @id) == created.entry
  end

  defp service(fixture) do
    sequence = :atomics.new(1, [])

    policy = fn
      [:reference_principal, _, _, :reference_policy] -> :ok
      _ -> :deny
    end

    assert {:ok, service} =
             Service.new(
               repository:
                 {RepositoryProbe,
                  %{repository: fixture.repository, observer: self(), faults: %{}}},
               authorization: {ReferenceAuthorization, %{observer: self(), policy: policy}},
               clock: {ReferenceClock, %{observer: self(), result: {:ok, @now}}},
               identifier:
                 {ReferenceIdentifier,
                  %{
                    observer: self(),
                    next: fn ->
                      {:ok, "urn:example:reference:#{:atomics.add_get(sequence, 1, 1)}"}
                    end
                  }},
               introduction: thing_description("urn:example:directory")
             )

    service
  end

  defp context(scope),
    do: Context.new!(:reference_principal, authorization: :reference_policy, repository: scope)

  defp at(service, seconds),
    do: %{
      service
      | clock: {ReferenceClock, %{observer: self(), result: {:ok, DateTime.add(@now, seconds)}}}
    }

  defp thing_description(identifier, title \\ "Reference Thing") do
    document = %{
      "@context" => "https://www.w3.org/2022/wot/td/v1.1",
      "title" => title,
      "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
      "security" => ["none"],
      "urn:example:extension" => %{"preserved" => true}
    }

    document = if identifier, do: Map.put(document, "id", identifier), else: document
    assert {:ok, value} = ThingDescription.from_map(document)
    value
  end

  defp fetch(%{repository: {module, state}, scope: scope}, identifier) do
    assert {:ok, entry} = module.fetch(state, identifier, scope)
    entry
  end

  defp assert_updated(mutation),
    do: assert({:ok, %Event{type: :thing_updated}} = Event.from_mutation(mutation))

  defp identifiers(page), do: Enum.map(page.entries, & &1.identifier)

  defp drain do
    receive do
      {:reference_port, _, _, _} -> drain()
      {:repository_callback, _, _} -> drain()
    after
      0 -> :ok
    end
  end
end
