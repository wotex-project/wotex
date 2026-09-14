defmodule Wotex.Directory.RepositoryContract do
  @moduledoc false

  import ExUnit.Assertions

  alias Wotex.Directory
  alias Wotex.Directory.{Context, Cursor, Entry, Error, Fixtures, Page, Query, Registration}
  alias Wotex.Directory.{RepositoryProbe, Service, TestAuthorization, TestClock, TestIdentifier}

  @now ~U[2026-09-02 10:00:00Z]
  @scenarios [
    fetch_insert: "repository contract: fetch and conditional insert preserve committed values",
    replace: "repository contract: replacement compares versions without changing failed state",
    delete: "repository contract: deletion compares versions without changing failed state",
    listing: "repository contract: listing is an ordered bounded keyset over active entries",
    revisions: "repository contract: mutations invalidate cursors and reads preserve generations",
    expiry: "repository contract: expiry is bounded atomic ordered and idempotent",
    isolation: "repository contract: every callback respects independent contexts",
    public_order:
      "repository contract: public operations authorize and forward explicit contexts",
    denial: "repository contract: denial reveals no existence and invokes no repository callback",
    failures: "repository contract: callback failures are redacted and never retried",
    invalid_pages: "repository contract: invalid repository pages never escape the public API",
    insert_contention: "repository contract: concurrent conditional creators have one winner",
    replace_contention:
      "repository contract: concurrent expected-version writers have one winner",
    delete_contention: "repository contract: concurrent expected-version deletes have one winner",
    expiry_contention:
      "repository contract: concurrent expiry batches never select an entry twice"
  ]

  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(_) do
    tests =
      for {scenario, name} <- @scenarios do
        quote do
          test unquote(name), %{repository_fixture: fixture} do
            Wotex.Directory.RepositoryContract.verify(unquote(scenario), fixture)
          end
        end
      end

    quote do
      (unquote_splicing(tests))
    end
  end

  @spec verify(atom(), map()) :: term()
  def verify(:fetch_insert, fixture) do
    entry = entry("one")
    generation = generation(fixture)
    assert absent?(call(fixture, :fetch, [entry.identifier]))
    assert call(fixture, :insert, [entry]) == {:ok, entry}
    assert call(fixture, :fetch, [entry.identifier]) == {:ok, entry}
    assert generation(fixture) == generation + 1
    assert call(fixture, :insert, [changed(entry)]) == {:error, :already_exists}
    assert call(fixture, :fetch, [entry.identifier]) == {:ok, entry}
    assert generation(fixture) == generation + 1
  end

  def verify(:replace, fixture) do
    entry = insert(fixture, entry("one"))
    replacement = changed(entry)
    generation = generation(fixture)
    assert call(fixture, :replace, [replacement, 2]) == {:error, :conflict}
    assert call(fixture, :replace, [entry("absent"), 1]) == {:error, :not_found}
    assert call(fixture, :fetch, [entry.identifier]) == {:ok, entry}
    assert generation(fixture) == generation
    assert call(fixture, :replace, [replacement, 1]) == {:ok, replacement}
    assert call(fixture, :fetch, [entry.identifier]) == {:ok, replacement}
    assert generation(fixture) == generation + 1
    assert call(fixture, :replace, [entry, 1]) == {:error, :conflict}
    assert generation(fixture) == generation + 1
  end

  def verify(:delete, fixture) do
    entry = insert(fixture, entry("one"))
    generation = generation(fixture)
    assert call(fixture, :delete, [entry.identifier, 2]) == {:error, :conflict}
    assert call(fixture, :delete, ["urn:example:absent", 1]) == {:error, :not_found}
    assert call(fixture, :fetch, [entry.identifier]) == {:ok, entry}
    assert generation(fixture) == generation
    assert call(fixture, :delete, [entry.identifier, 1]) == :ok
    assert absent?(call(fixture, :fetch, [entry.identifier]))
    assert call(fixture, :delete, [entry.identifier, 1]) == {:error, :not_found}
    assert generation(fixture) == generation + 1
  end

  def verify(:listing, fixture) do
    for name <- ["中", "é", "a", "Z"], do: insert(fixture, entry(name))
    insert(fixture, entry("expired", 0))
    insert(fixture, %{entry("retained") | state: :expired})
    first = page(fixture, 2)
    assert ids(first.entries) == [identifier("Z"), identifier("a")]
    assert Page.validate(first, query(2), @now) == :ok
    assert {:ok, cursor} = Cursor.decode(first.next_cursor)
    second = page(fixture, 2, cursor)
    assert ids(second.entries) == [identifier("é"), identifier("中")]
    assert second.next_cursor == nil
    assert second.collection_revision == first.collection_revision
    assert Enum.all?(first.entries ++ second.entries, &is_nil(&1.registration.retrieved))

    insert(fixture, entry("b", 1))
    before_expiry = page(fixture, 2)
    assert {:ok, cursor} = Cursor.decode(before_expiry.next_cursor)
    after_expiry = page(fixture, 4, cursor, DateTime.add(@now, 1))
    assert ids(after_expiry.entries) == [identifier("é"), identifier("中")]
    assert after_expiry.collection_revision == before_expiry.collection_revision
  end

  def verify(:revisions, fixture) do
    first = insert(fixture, entry("a"))
    insert(fixture, entry("b"))
    insert(fixture, entry("d"))

    for mutation <- [:insert, :replace, :delete, :expire_due] do
      before = page(fixture, 1)
      assert {:ok, cursor} = Cursor.decode(before.next_cursor)
      generation = generation(fixture)
      mutate(fixture, mutation, first)
      assert generation(fixture) == generation + 1
      assert call(fixture, :list, [query(1), cursor, @now]) == {:error, :collection_changed}
      assert generation(fixture) == generation + 1
    end
  end

  def verify(:expiry, fixture) do
    for name <- ["c", "a", "b"], do: insert(fixture, entry(name, 1))
    future = insert(fixture, entry("future", 2))
    generation = generation(fixture)
    assert call(fixture, :expire_due, [@now, 2, :retain]) == {:ok, []}
    assert generation(fixture) == generation
    cutoff = DateTime.add(@now, 1)
    assert {:ok, retained} = call(fixture, :expire_due, [cutoff, 2, :retain])
    assert ids(retained) == [identifier("a"), identifier("b")]
    assert Enum.all?(retained, &(&1.state == :expired and &1.version == 2))
    assert generation(fixture) == generation + 1
    for entry <- retained, do: assert(call(fixture, :fetch, [entry.identifier]) == {:ok, entry})
    assert {:ok, purged} = call(fixture, :expire_due, [cutoff, 4, :purge])
    assert ids(purged) == [identifier("a"), identifier("b"), identifier("c")]
    assert generation(fixture) == generation + 2
    for entry <- purged, do: assert(absent?(call(fixture, :fetch, [entry.identifier])))
    assert call(fixture, :fetch, [future.identifier]) == {:ok, future}
    assert call(fixture, :expire_due, [cutoff, 4, :retain]) == {:ok, []}
    assert call(fixture, :expire_due, [cutoff, 4, :purge]) == {:ok, []}
    assert generation(fixture) == generation + 2
  end

  def verify(:isolation, fixture) do
    other = %{fixture | scope: fixture.other_scope}
    original = insert(fixture, entry("shared", 0))
    independent = insert(other, changed(entry("shared", 0)))
    other_generation = generation(other)
    assert call(fixture, :fetch, [original.identifier]) == {:ok, original}
    assert call(other, :fetch, [original.identifier]) == {:ok, independent}
    assert call(fixture, :replace, [changed(original), 1]) == {:ok, changed(original)}
    assert call(other, :fetch, [original.identifier]) == {:ok, independent}
    assert call(fixture, :delete, [original.identifier, 2]) == :ok
    assert call(other, :fetch, [original.identifier]) == {:ok, independent}
    assert call(fixture, :expire_due, [@now, 4, :purge]) == {:ok, []}
    assert generation(other) == other_generation

    assert call(other, :expire_due, [@now, 4, :retain]) ==
             {:ok, [%{independent | version: 3, state: :expired}]}

    assert generation(fixture) == 3
    insert(fixture, entry("visible"))
    assert ids(page(fixture).entries) == [identifier("visible")]
    assert page(other).entries == []
  end

  def verify(:public_order, fixture) do
    service = service(fixture)
    context = context(fixture.scope)
    thing = Fixtures.thing_description(identifier("public"))
    assert {:ok, created} = Directory.register(service, thing, context)
    assert_trace(context, :register, [:fetch, :insert])
    assert {:ok, fetched} = Directory.get(service, created.entry.identifier, context)
    assert fetched.registration.retrieved == @now
    assert_trace(context, :get, [:fetch])
    assert call(fixture, :fetch, [created.entry.identifier]) == {:ok, created.entry}

    for operation <- [:replace, :patch, :list, :query, :expire, :delete] do
      assert {:ok, _} = public_call(operation, service, context, thing)
      callbacks = callbacks(operation)
      assert_trace(context, authorization_operation(operation), callbacks)
    end

    assert {:ok, introduction} = Directory.introduction(service)
    assert introduction.path == "/.well-known/wot"
    assert trace() == []
  end

  def verify(:denial, fixture) do
    thing = Fixtures.thing_description(identifier("denied"))
    service = service(fixture)

    denied = %{
      service
      | authorization: {TestAuthorization, %{test_pid: self(), result: {:error, :forbidden}}}
    }

    context = context(fixture.scope)

    for operation <- [:register, :get, :replace, :patch, :delete, :list, :query, :expire] do
      absent_result = public_call(operation, denied, context, thing)
      assert {:error, %Error{code: :forbidden}} = absent_result
      assert_no_repository_calls()
      assert {:ok, _} = Directory.register(service, thing, context)
      trace()
      assert public_call(operation, denied, context, thing) == absent_result
      assert_no_repository_calls()
      assert {:ok, _} = Directory.delete(service, identifier("denied"), context)
      trace()
    end

    target = {:entry, identifier("denied")}

    named_denial = %{
      service
      | authorization:
          {TestAuthorization,
           %{test_pid: self(), results: %{{:register, target} => {:error, :forbidden}}}}
    }

    assert {:error, %Error{code: :forbidden}} =
             Directory.register(named_denial, thing, context)

    assert_no_repository_calls()
    assert {:ok, _} = Directory.register(service, thing, context)
    trace()

    assert {:error, %Error{code: :forbidden}} =
             Directory.register(named_denial, thing, context)

    assert_no_repository_calls()
  end

  def verify(:failures, fixture) do
    thing = Fixtures.thing_description(identifier("failure"))
    context = context(fixture.scope)
    service = service(fixture)
    assert {:ok, created} = Directory.register(service, thing, context)
    trace()
    generation = generation(fixture)

    for {operation, callback} <- [
          get: :fetch,
          register: :insert,
          replace: :replace,
          patch: :replace,
          delete: :delete,
          list: :list,
          expire: :expire_due
        ] do
      assert_callback_failure(fixture, service, context, thing, operation, callback)
      assert call(fixture, :fetch, [created.entry.identifier]) == {:ok, created.entry}
      assert generation(fixture) == generation
    end
  end

  def verify(:invalid_pages, fixture) do
    first = insert(fixture, entry("a"))
    second = insert(fixture, entry("b"))
    service = service(fixture)
    context = context(fixture.scope)
    valid = page(fixture)

    for entries <- [[second, first], [first, first], [%{first | state: :expired}]] do
      faulty = fault(service, :list, {:ok, %{valid | entries: entries}})
      assert {:error, %Error{code: :invalid_page}} = Directory.list(faulty, context)
      assert_trace(context, :list, [:list])
    end

    faulty = fault(service, :list, {:ok, valid})
    assert {:error, %Error{code: :invalid_page}} = Directory.list(faulty, context, limit: 1)
    assert_trace(context, :list, [:list])
  end

  def verify(:insert_contention, fixture) do
    entry = entry("race")
    results = contend(fn -> call(fixture, :insert, [entry]) end)
    assert Enum.count(results, &(&1 == {:ok, entry})) == 1
    assert Enum.count(results, &(&1 == {:error, :already_exists})) == 7
    assert call(fixture, :fetch, [entry.identifier]) == {:ok, entry}
    assert generation(fixture) == 1
  end

  def verify(:replace_contention, fixture) do
    entry = insert(fixture, entry("race"))
    replacement = changed(entry)
    results = contend(fn -> call(fixture, :replace, [replacement, 1]) end)
    assert Enum.count(results, &(&1 == {:ok, replacement})) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 7
    assert call(fixture, :fetch, [entry.identifier]) == {:ok, replacement}
    assert generation(fixture) == 2
  end

  def verify(:delete_contention, fixture) do
    entry = insert(fixture, entry("race"))
    results = contend(fn -> call(fixture, :delete, [entry.identifier, 1]) end)
    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :not_found})) == 7
    assert absent?(call(fixture, :fetch, [entry.identifier]))
    assert generation(fixture) == 2
  end

  def verify(:expiry_contention, fixture) do
    for name <- ["a", "b", "c", "d"], do: insert(fixture, entry(name, 0))
    results = contend(fn -> call(fixture, :expire_due, [@now, 2, :retain]) end)
    entries = Enum.flat_map(results, fn {:ok, entries} -> entries end)
    assert Enum.sort(ids(entries)) == Enum.map(["a", "b", "c", "d"], &identifier/1)
    assert Enum.all?(entries, &(&1.version == 2 and &1.state == :expired))
    assert Enum.all?(results, fn {:ok, batch} -> length(batch) <= 2 end)
    assert generation(fixture) == 6
  end

  defp assert_callback_failure(fixture, service, context, thing, operation, callback) do
    failures = [{:error, %{private_reason: "synthetic-secret"}}, :malformed_return]

    for failure <- failures do
      faulty = fault(service, callback, failure)
      input = if operation == :register, do: Fixtures.thing_description(nil), else: thing

      assert {:error, %Error{code: :repository_failure} = error} =
               public_call(operation, faulty, context, input)

      refute inspect(error) =~ "synthetic-secret"
      refute inspect(error) =~ "private_reason"

      assert_trace(
        context,
        operation,
        if(operation == :register, do: [:insert], else: callbacks(operation))
      )

      assert page(%{fixture | scope: fixture.other_scope}).entries == []
    end
  end

  defp service(fixture) do
    {:ok, service} =
      Service.new(
        repository:
          {RepositoryProbe, %{repository: fixture.repository, observer: self(), faults: %{}}},
        authorization: {TestAuthorization, %{test_pid: self(), result: :ok}},
        clock: {TestClock, @now},
        identifier: {TestIdentifier, fixture.identifier},
        introduction: Fixtures.thing_description("urn:example:directory"),
        default_page_limit: 4,
        max_page_limit: 8,
        default_expiry_batch_limit: 4,
        max_expiry_batch_limit: 8
      )

    service
  end

  defp context(scope),
    do:
      Context.new!({:principal, scope}, authorization: {:authorization, scope}, repository: scope)

  defp fault(service, callback, result) do
    {RepositoryProbe, state} = service.repository
    %{service | repository: {RepositoryProbe, %{state | faults: %{callback => result}}}}
  end

  defp public_call(:register, service, context, thing),
    do: Directory.register(service, thing, context)

  defp public_call(:get, service, context, thing),
    do: Directory.get(service, Wotex.ThingDescription.id(thing), context)

  defp public_call(:replace, service, context, thing),
    do: Directory.replace(service, Wotex.ThingDescription.id(thing), thing, context)

  defp public_call(:patch, service, context, thing),
    do:
      Directory.patch(service, Wotex.ThingDescription.id(thing), %{"title" => "Changed"}, context)

  defp public_call(:delete, service, context, thing),
    do: Directory.delete(service, Wotex.ThingDescription.id(thing), context)

  defp public_call(:list, service, context, _), do: Directory.list(service, context)

  defp public_call(:query, service, context, _),
    do: Directory.query(service, query(4), context)

  defp public_call(:expire, service, context, _), do: Directory.expire(service, context)

  defp callbacks(operation) when operation in [:get], do: [:fetch]
  defp callbacks(operation) when operation in [:replace, :patch], do: [:fetch, :replace]
  defp callbacks(:delete), do: [:fetch, :delete]
  defp callbacks(operation) when operation in [:list, :query], do: [:list]
  defp callbacks(:expire), do: [:expire_due]
  defp authorization_operation(:query), do: :list
  defp authorization_operation(operation), do: operation

  defp assert_trace(context, operation, expected_callbacks) do
    events = trace()
    repository_calls = for {:repository_callback, callback, _} <- events, do: callback
    assert repository_calls == expected_callbacks

    Enum.reduce(events, [], fn
      {:authorize, principal, ^operation, target, authorization}, targets ->
        assert principal == context.principal
        assert authorization == context.authorization
        [target | targets]

      {:repository_callback, callback, arguments}, targets ->
        assert List.last(arguments) == context.repository
        target = target(callback, arguments)
        assert target in targets
        targets
    end)
  end

  defp target(callback, _) when callback in [:list, :expire_due, :insert], do: :collection
  defp target(:replace, [entry | _]), do: {:entry, entry.identifier}
  defp target(_, [identifier | _]), do: {:entry, identifier}

  defp assert_no_repository_calls do
    events = trace()
    assert events != []
    assert Enum.all?(events, &match?({:authorize, _, _, _, _}, &1))
  end

  defp trace do
    receive do
      {:repository_callback, _, _} = event -> [event | trace()]
      {:authorize, _, _, _, _} = event -> [event | trace()]
    after
      0 -> []
    end
  end

  defp call(%{repository: {module, state}, scope: scope}, callback, arguments),
    do: apply(module, callback, [state | arguments] ++ [scope])

  defp insert(fixture, entry) do
    assert call(fixture, :insert, [entry]) == {:ok, entry}
    entry
  end

  defp entry(name, ttl \\ nil) do
    input = if is_nil(ttl), do: :absent, else: {:present, %{"ttl" => ttl}}
    assert {:ok, registration} = Registration.create(@now, input, :register)

    td =
      Fixtures.thing_description(identifier(name), %{
        "urn:example:extension" => %{"a" => [1, nil]}
      })

    assert {:ok, entry} = Entry.new(identifier(name), td, registration)
    entry
  end

  defp changed(entry) do
    td = Fixtures.thing_description(entry.identifier, %{"title" => "Replacement"})
    %{entry | version: entry.version + 1, thing_description: td}
  end

  defp identifier(name), do: "urn:example:thing:" <> name
  defp absent?(result), do: result in [:not_found, {:error, :not_found}]
  defp query(limit), do: %Query{profile: :listing, limit: limit, format: :array}

  defp page(fixture, limit \\ 8, cursor \\ nil, active_at \\ @now) do
    assert {:ok, page} = call(fixture, :list, [query(limit), cursor, active_at])
    page
  end

  defp generation(fixture), do: fixture.generation.(page(fixture).collection_revision)
  defp ids(entries), do: Enum.map(entries, & &1.identifier)

  defp mutate(fixture, :insert, _), do: insert(fixture, entry("c", 0))
  defp mutate(fixture, :replace, entry), do: call(fixture, :replace, [changed(entry), 1])
  defp mutate(fixture, :delete, _), do: call(fixture, :delete, [identifier("b"), 1])
  defp mutate(fixture, :expire_due, _), do: call(fixture, :expire_due, [@now, 2, :purge])

  defp contend(operation) do
    parent = self()
    token = make_ref()

    tasks =
      for _ <- 1..8 do
        Task.async(fn ->
          send(parent, {:ready, self(), token})

          receive do
            {:go, ^token} -> operation.()
          after
            5_000 -> flunk("repository contender did not receive its start signal")
          end
        end)
      end

    for task <- tasks, do: assert_receive({:ready, pid, ^token} when pid == task.pid, 5_000)
    for task <- tasks, do: send(task.pid, {:go, token})
    Enum.map(tasks, &Task.await(&1, 5_000))
  end
end
