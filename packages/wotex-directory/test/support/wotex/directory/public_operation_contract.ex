defmodule Wotex.Directory.PublicOperationContract do
  @moduledoc false

  import ExUnit.Assertions

  alias Wotex.Directory
  alias Wotex.Directory.{Context, Entry, Error, Event, Expiry, Fixtures, Mutation, Page, Query}
  alias Wotex.Directory.{RepositoryBarrier, Service, TestAuthorization, TestClock, TestIdentifier}

  @now ~U[2026-09-02 10:00:00Z]
  @writes [:register, :replace, :patch, :delete]
  @mutations [:create, :register, :replace, :patch, :delete, :retain, :purge]

  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(_) do
    scenarios =
      for(winner <- @writes, loser <- @writes, do: {:competing, winner, loser}) ++
        for(
          operation <- @mutations,
          phase <- [:before, :after],
          do: {:interrupted, operation, phase}
        ) ++
        for(operation <- @mutations, do: {:paging_mutation, operation}) ++
        [
          :create_race,
          :invalid_patch,
          {:failed_reply, :before},
          {:failed_reply, :after},
          :paging_expiry,
          :paging_empty,
          :paging_snapshot
        ]

    tests =
      for scenario <- scenarios do
        quote do
          test unquote("public operation contract: #{inspect(scenario)}"), %{
            repository_fixture: fixture
          } do
            Wotex.Directory.PublicOperationContract.verify(
              unquote(Macro.escape(scenario)),
              fixture
            )
          end
        end
      end

    quote do
      (unquote_splicing(tests))
    end
  end

  @spec verify(atom() | tuple(), map()) :: term()
  def verify({:competing, winner, loser}, fixture) do
    service = service(fixture)
    context = context(fixture)
    original = seed(service, context)
    revision = generation(service, context, fixture)
    paused = pause(service, [{:fetch, :after}, {:replace, :before}, {:delete, :before}])
    winning = start(fn -> mutate(winner, paused, context, "Winner") end)
    losing = start(fn -> mutate(loser, paused, context, "Loser") end)

    for caller <- [winning, losing] do
      {reference, {:ok, fetched}} = checkpoint(caller, :fetch, :after)
      assert fetched == original
      resume(caller, reference)
    end

    {winner_ref, winner_arguments} = checkpoint(winning, callback(winner), :before)
    {loser_ref, loser_arguments} = checkpoint(losing, callback(loser), :before)
    assert Enum.at(winner_arguments, 1) == 1
    assert Enum.at(loser_arguments, 1) == 1
    resume(winning, winner_ref)
    {winner_result, winner_event} = finish(winning)
    assert {:ok, %Mutation{operation: ^winner}} = winner_result
    assert {:ok, %Event{}} = winner_event
    resume(losing, loser_ref)
    {loser_result, nil} = finish(losing)
    assert_failure(loser_result, if(winner == :delete, do: :not_found, else: :conflict))
    assert_calls(winning, [:fetch, callback(winner)])
    assert_calls(losing, [:fetch, callback(loser)])
    assert generation(service, context, fixture) == revision + 1
    assert_winner(service, context, winner, winner_result)
  end

  def verify(:create_race, fixture) do
    service = service(fixture)
    context = context(fixture)
    paused = pause(service, [{:fetch, :after}, {:insert, :before}])
    winning = start(fn -> mutate(:create, paused, context, "Winner") end)
    losing = start(fn -> mutate(:create, paused, context, "Loser") end)

    for caller <- [winning, losing] do
      {reference, absent} = checkpoint(caller, :fetch, :after)
      assert absent in [:not_found, {:error, :not_found}]
      resume(caller, reference)
    end

    {winner_ref, _} = checkpoint(winning, :insert, :before)
    {loser_ref, _} = checkpoint(losing, :insert, :before)
    resume(winning, winner_ref)
    {{:ok, winner}, {:ok, %Event{type: :thing_created}}} = finish(winning)
    assert winner.status == :created
    resume(losing, loser_ref)
    {failure, nil} = finish(losing)
    assert_failure(failure, :conflict)
    assert_calls(winning, [:fetch, :insert])
    assert_calls(losing, [:fetch, :insert])
    assert generation(service, context, fixture) == 1
    assert_winner(service, context, :create, {:ok, winner})

    assert {:ok, repeated} = mutate(:create, service, context, "Loser")
    assert repeated.status == :replaced
    assert repeated.entry.version == 2
    assert repeated.entry.registration.created == winner.entry.registration.created
    assert generation(service, context, fixture) == 2
  end

  def verify(:invalid_patch, fixture) do
    service = service(fixture)
    context = context(fixture)
    original = seed(service, context)
    paused = pause(service, [{:fetch, :after}])

    caller =
      start(fn ->
        Directory.patch(paused, identifier(), %{"title" => nil}, context, if_version: 1)
      end)

    {reference, {:ok, fetched}} = checkpoint(caller, :fetch, :after)
    assert fetched == original
    assert {:ok, winner} = mutate(:patch, service, context, "Winner")
    resume(caller, reference)
    {failure, nil} = finish(caller)
    assert_failure(failure, :invalid_thing_description)
    assert_calls(caller, [:fetch])
    assert_winner(service, context, :patch, {:ok, winner})
    assert generation(service, context, fixture) == 2
  end

  def verify({:interrupted, operation, phase}, fixture) do
    service = service(fixture)
    context = context(fixture)
    original = prepare(service, context, operation)
    service = operation_clock(service, operation)
    revision = generation(service, context, fixture)
    paused = pause(service, [{callback(operation), phase}])
    caller = start(fn -> mutate(operation, paused, context, "Interrupted") end)
    {_, boundary_value} = checkpoint(caller, callback(operation), phase)
    interrupt(caller)
    assert_calls(caller, operation_callbacks(operation))

    case phase do
      :before ->
        assert stored(fixture) == original
        assert generation(service, context, fixture) == revision
        assert {:ok, _} = mutate(operation, service, context, "Repeated")
        assert generation(service, context, fixture) == revision + 1

      :after ->
        assert_committed(fixture, operation, boundary_value)
        assert generation(service, context, fixture) == revision + 1
        assert_repeat(operation, service, context, fixture, revision + 1)
    end
  end

  def verify({:failed_reply, phase}, fixture) do
    service = service(fixture)
    context = context(fixture)
    original = seed(service, context)
    paused = pause(service, [{:replace, phase}])
    caller = start(fn -> mutate(:patch, paused, context, "Committed") end)
    {reference, boundary_value} = checkpoint(caller, :replace, phase)
    resume(caller, reference, {:return, {:error, %{credential: "synthetic-secret"}}})
    {failure, nil} = finish(caller)
    assert_failure(failure, :repository_failure)
    refute inspect(failure) =~ "synthetic-secret"
    assert_calls(caller, [:fetch, :replace])

    if phase == :before do
      assert stored(fixture) == original
      assert generation(service, context, fixture) == 1
    else
      assert_committed(fixture, :patch, boundary_value)
      assert generation(service, context, fixture) == 2
      assert_failure(mutate(:patch, service, context, "Repeated"), :conflict)
      assert generation(service, context, fixture) == 2
    end
  end

  def verify({:paging_mutation, operation}, fixture) do
    service = service(fixture)
    context = context(fixture)
    seed(service, context, "a")
    seed(service, context, "one", 1)
    seed(service, context, "z")
    assert {:ok, first} = Directory.list(service, context, limit: 1)
    next = Page.next_query(first, query())
    later = operation_clock(service, operation)
    paused = pause(later, [{:list, :before}])
    caller = start(fn -> Directory.query(paused, next, context) end)
    {reference, _} = checkpoint(caller, :list, :before)

    result =
      if operation == :create do
        Directory.register(service, thing("new"), context)
      else
        mutate(operation, later, context, "Changed")
      end

    assert {:ok, _} = result

    resume(caller, reference)
    {failure, nil} = finish(caller)
    assert_failure(failure, :collection_changed)
    assert_calls(caller, [:list])

    assert generation(later, context, fixture) ==
             fixture.generation.(first.collection_revision) + 1

    assert {:ok, restarted} = Directory.list(later, context, limit: 8)
    assert ids(restarted.entries) == expected_identifiers(operation)
  end

  def verify(:paging_expiry, fixture) do
    service = service(fixture)
    context = context(fixture)

    for {name, ttl} <- [{"a", 1}, {"b", 1}, {"c", 2}, {"d", 1}, {"e", nil}, {"f", 2}, {"g", nil}],
        do: seed(service, context, name, ttl)

    assert {:ok, first} = Directory.query(service, query(), context)
    assert ids(first.entries) == [identifier("a")]
    revision = first.collection_revision

    last =
      Enum.reduce([{"c", 1}, {"e", 2}, {"g", 2}], first, fn {name, seconds}, previous ->
        next = Page.next_query(previous, query())
        assert next.limit == 1
        assert next.format == :collection
        later = at(service, seconds)
        caller = start(fn -> Directory.query(later, next, context) end)
        {{:ok, page}, nil} = finish(caller)
        assert ids(page.entries) == [identifier(name)]
        assert page.collection_revision == revision
        assert hd(page.entries).registration.retrieved == DateTime.add(@now, seconds)
        page
      end)

    assert last.next_cursor == nil
    assert generation(service, context, fixture) == 7

    for name <- ["a", "b", "c", "d", "e", "f", "g"] do
      assert {:ok, entry} = fetch(fixture, identifier(name))
      assert entry.version == 1
      assert entry.state == :active
      assert entry.registration.retrieved == nil
    end
  end

  def verify(:paging_empty, fixture) do
    service = service(fixture)
    context = context(fixture)
    for name <- ["a", "b", "c"], do: seed(service, context, name, 1)
    assert {:ok, first} = Directory.query(service, query(), context)
    next = Page.next_query(first, query())
    caller = start(fn -> Directory.query(at(service, 1), next, context) end)
    {{:ok, resumed}, nil} = finish(caller)
    assert resumed.entries == []
    assert resumed.next_cursor == nil
    assert resumed.collection_revision == first.collection_revision
    assert generation(service, context, fixture) == 3
  end

  def verify(:paging_snapshot, fixture) do
    service = service(fixture)
    context = context(fixture)
    for name <- ["a", "b", "c"], do: seed(service, context, name)
    paused = pause(service, [{:list, :after}])
    caller = start(fn -> Directory.query(paused, query(), context) end)
    {reference, {:ok, snapshot}} = checkpoint(caller, :list, :after)
    assert {:ok, _} = Directory.register(service, thing("d"), context)
    resume(caller, reference)
    {{:ok, returned}, nil} = finish(caller)
    assert returned.collection_revision == snapshot.collection_revision
    assert ids(returned.entries) == [identifier("a")]
    assert_calls(caller, [:list])

    assert_failure(
      Directory.query(service, Page.next_query(returned, query()), context),
      :collection_changed
    )

    assert generation(service, context, fixture) == 4
  end

  defp service(fixture) do
    {:ok, service} =
      Service.new(
        repository: fixture.repository,
        authorization: {TestAuthorization, %{result: :ok}},
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

  defp context(fixture),
    do: Context.new!(:principal, authorization: :authorization, repository: fixture.scope)

  defp pause(service, checkpoints),
    do: %{
      service
      | repository:
          {RepositoryBarrier,
           %{repository: service.repository, observer: self(), checkpoints: checkpoints}}
    }

  defp start(operation) do
    observer = self()
    token = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        result = operation.()

        event =
          case result do
            {:ok, %Mutation{} = mutation} -> Event.from_mutation(mutation)
            _ -> nil
          end

        send(observer, {:operation_result, self(), token, result, event})
      end)

    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    %{pid: pid, monitor: monitor, token: token}
  end

  defp checkpoint(%{pid: pid}, callback, phase) do
    assert_receive {:repository_checkpoint, ^pid, reference, ^callback, ^phase, value}, 5_000
    {reference, value}
  end

  defp resume(%{pid: pid}, reference, action \\ :continue),
    do: send(pid, {:repository_continue, reference, action})

  defp finish(%{pid: pid, monitor: monitor, token: token}) do
    assert_receive {:operation_result, ^pid, ^token, result, event}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
    {result, event}
  end

  defp interrupt(%{pid: pid, monitor: monitor, token: token}) do
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
    refute_received {:operation_result, ^pid, ^token, _, _}
  end

  defp assert_calls(%{pid: pid}, expected), do: assert(calls(pid) == expected)

  defp calls(pid) do
    receive do
      {:repository_call, ^pid, callback, _} -> [callback | calls(pid)]
    after
      0 -> []
    end
  end

  defp assert_failure(result, code) do
    assert {:error, %Error{code: ^code}} = result
    assert {:error, %Error{code: :invalid_request}} = Event.from_mutation(elem(result, 1))
  end

  defp seed(service, context, name \\ "one", ttl \\ nil) do
    options = if ttl == nil, do: [], else: [registration: %{"ttl" => ttl}]
    assert {:ok, mutation} = Directory.register(service, thing(name), context, options)
    mutation.entry
  end

  defp prepare(_, _, :create), do: nil

  defp prepare(service, context, operation) when operation in [:retain, :purge],
    do: seed(service, context, "one", 1)

  defp prepare(service, context, _), do: seed(service, context)

  defp mutate(operation, service, context, title) when operation in [:create, :register],
    do: Directory.register(service, thing("one", title), context)

  defp mutate(:replace, service, context, title),
    do: Directory.replace(service, identifier(), thing("one", title), context, if_version: 1)

  defp mutate(:patch, service, context, title),
    do: Directory.patch(service, identifier(), %{"title" => title}, context, if_version: 1)

  defp mutate(:delete, service, context, _),
    do: Directory.delete(service, identifier(), context, if_version: 1)

  defp mutate(strategy, service, context, _) when strategy in [:retain, :purge],
    do: Directory.expire(service, context, strategy: strategy, limit: 2)

  defp callback(:create), do: :insert
  defp callback(:delete), do: :delete
  defp callback(operation) when operation in [:retain, :purge], do: :expire_due
  defp callback(_), do: :replace

  defp operation_callbacks(operation) when operation in [:retain, :purge], do: [:expire_due]
  defp operation_callbacks(operation), do: [:fetch, callback(operation)]

  defp operation_clock(service, operation) when operation in [:retain, :purge], do: at(service, 1)
  defp operation_clock(service, _), do: service
  defp at(service, seconds), do: %{service | clock: {TestClock, DateTime.add(@now, seconds)}}
  defp identifier(name \\ "one"), do: "urn:example:thing:" <> name

  defp thing(name, title \\ "Original"),
    do: Fixtures.thing_description(identifier(name), %{"title" => title})

  defp query, do: %Query{profile: :listing, limit: 1, format: :collection}
  defp ids(entries), do: Enum.map(entries, & &1.identifier)

  defp generation(service, context, fixture) do
    assert {:ok, page} = Directory.list(service, context, limit: 8)
    fixture.generation.(page.collection_revision)
  end

  defp fetch(%{repository: {module, state}, scope: scope}, identifier),
    do: module.fetch(state, identifier, scope)

  defp stored(fixture) do
    case fetch(fixture, identifier()) do
      {:ok, entry} -> entry
      absent when absent in [:not_found, {:error, :not_found}] -> nil
    end
  end

  defp assert_winner(service, context, :delete, _),
    do: assert_failure(Directory.get(service, identifier(), context), :not_found)

  defp assert_winner(service, context, _, {:ok, mutation}) do
    assert {:ok, fetched} = Directory.get(service, identifier(), context)
    assert Entry.for_storage(fetched) == mutation.entry
    assert Wotex.ThingDescription.to_map(fetched.thing_description)["title"] == "Winner"
  end

  defp assert_committed(fixture, operation, {:ok, entry})
       when operation in [:create, :register, :replace, :patch],
       do: assert(stored(fixture) == entry)

  defp assert_committed(fixture, :delete, :ok), do: assert(stored(fixture) == nil)

  defp assert_committed(fixture, :retain, {:ok, [entry]}) do
    assert entry.state == :expired
    assert entry.version == 2
    assert stored(fixture) == entry
  end

  defp assert_committed(fixture, :purge, {:ok, [_]}), do: assert(stored(fixture) == nil)

  defp assert_repeat(operation, service, context, fixture, revision)
       when operation in [:create, :register] do
    previous = stored(fixture)
    assert {:ok, repeated} = mutate(operation, service, context, "Repeated")
    assert repeated.status == :replaced
    assert repeated.entry.version == previous.version + 1
    assert repeated.entry.registration.created == previous.registration.created
    assert generation(service, context, fixture) == revision + 1
  end

  defp assert_repeat(operation, service, context, fixture, revision) do
    previous = stored(fixture)
    result = mutate(operation, service, context, "Repeated")

    case operation do
      :delete -> assert_failure(result, :not_found)
      expiry when expiry in [:retain, :purge] -> assert {:ok, %Expiry{entries: []}} = result
      _ -> assert_failure(result, :conflict)
    end

    assert stored(fixture) == previous
    assert generation(service, context, fixture) == revision
  end

  defp expected_identifiers(:create), do: Enum.map(["a", "new", "one", "z"], &identifier/1)

  defp expected_identifiers(operation) when operation in [:delete, :retain, :purge],
    do: Enum.map(["a", "z"], &identifier/1)

  defp expected_identifiers(_), do: Enum.map(["a", "one", "z"], &identifier/1)
end
