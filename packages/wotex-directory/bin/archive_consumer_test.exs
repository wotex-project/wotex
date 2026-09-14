defmodule ArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use Wotex.Directory.RepositoryContract
  use Wotex.Directory.PublicOperationContract
  use Wotex.Directory.ReferenceConsumerContract

  alias Wotex.Directory
  alias Wotex.Directory.{Context, Error, Fixtures, MemoryRepository, ScopedMemoryRepository}
  alias Wotex.Directory.{Service, TestAuthorization, TestClock, TestIdentifier}

  setup do
    repositories =
      Map.new([:scope_a, :scope_b], fn scope ->
        {scope, start_supervised!(%{id: scope, start: {MemoryRepository, :start_link, [[]]}})}
      end)

    identifier =
      start_supervised!(%{
        id: :identifier,
        start: {TestIdentifier, :start_link, [List.duplicate("urn:example:anonymous", 4)]}
      })

    %{
      repository_fixture: %{
        repository: {ScopedMemoryRepository, repositories},
        scope: :scope_a,
        other_scope: :scope_b,
        identifier: identifier,
        generation: fn "generation:" <> value -> String.to_integer(value) end
      }
    }
  end

  test "archive-only register, retrieve, patch, list, expire and negative operations", %{
    repository_fixture: fixture
  } do
    now = ~U[2026-09-02 10:00:00Z]
    context = Context.new!(:principal, repository: fixture.scope)
    id = "urn:example:archive"

    assert {:ok, service} =
             Service.new(
               repository: fixture.repository,
               authorization: {TestAuthorization, %{result: :ok}},
               clock: {TestClock, now},
               identifier: {TestIdentifier, fixture.identifier},
               introduction: Fixtures.thing_description("urn:example:directory")
             )

    assert {:ok, created} =
             Directory.register(service, Fixtures.thing_description(id), context,
               registration: %{"ttl" => 1}
             )

    assert created.status == :created
    assert {:ok, fetched} = Directory.get(service, id, context)
    assert fetched.registration.retrieved == now

    assert {:error, %Error{code: :invalid_thing_description}} =
             Directory.patch(service, id, %{"title" => nil}, context)

    assert {:ok, patched} =
             Directory.patch(service, id, %{"title" => "Patched"}, context, if_version: 1)

    assert patched.entry.version == 2

    assert {:error, %Error{code: :conflict}} =
             Directory.delete(service, id, context, if_version: 1)

    assert {:ok, page} = Directory.list(service, context)
    assert Enum.map(page.entries, & &1.identifier) == [id]
    later = %{service | clock: {TestClock, DateTime.add(now, 1)}}
    assert {:error, %Error{code: :expired}} = Directory.get(later, id, context)
    assert {:ok, expiry} = Directory.expire(later, context)
    assert Enum.map(expiry.entries, & &1.identifier) == [id]
    assert {:error, %Error{code: :not_found}} = Directory.get(later, id, context)
    assert {:ok, %{entries: []}} = Directory.expire(later, context)
  end
end
