Code.require_file("../../support/bridge_wire_fixture.ex", __DIR__)

defmodule Wotex.Matter.BridgeConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Matter.Bridge.{ClockProjection, Consumer}
  alias Wotex.Matter.{BridgeWireFixture, Error}
  alias Wotex.Runtime.{Context, ExposedThing}
  alias Wotex.ThingDescription

  @moduletag :capture_log

  setup do
    test = self()
    clock = start_supervised!({Agent, fn -> 1000 end})

    handlers =
      Map.new([:readproperty, :writeproperty, :invokeaction], fn operation ->
        name = if operation == :invokeaction, do: "set", else: "value"

        {{operation, name},
         fn input, context ->
           send(test, {:handler, operation, input, context})
           {:ok, input}
         end}
      end)

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Bridge execution fixture",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "value" => %{"type" => "integer", "forms" => [%{"href" => "https://example.test/value"}]}
        },
        "actions" => %{"set" => %{"forms" => [%{"href" => "https://example.test/set"}]}}
      })

    {:ok, exposed} = ExposedThing.new(td, handlers)

    input = fn value, context ->
      send(test, {:input, value, context})
      {:ok, value}
    end

    result = fn value, context ->
      send(test, {:result, value, context})
      :completed
    end

    policy = fn request, context ->
      send(test, {:policy, request, context})
      :allow
    end

    routes =
      Map.new(
        [
          {:read, 0, :readproperty, "value"},
          {:write, 0x4001, :writeproperty, "value"},
          {:invoke, 0, :invokeaction, "set"}
        ],
        fn {native, member, operation, name} ->
          {{<<0, 255>>, 3, 6, member, native},
           %{exposed: exposed, operation: operation, name: name, input: input, result: result}}
        end
      )

    options = [
      generation: BridgeWireFixture.generation(),
      receiver: test,
      policy: policy,
      clock: fn -> Agent.get(clock, & &1) end,
      routes: routes
    ]

    %{clock: clock, options: options, routes: routes, exposed: exposed}
  end

  defp owner(options), do: start_supervised!({Consumer, options}, id: make_ref())

  defp projection(now \\ 1000, native \\ 0) do
    {:ok, value} = ClockProjection.new(BridgeWireFixture.generation(), now, now, native, {1, 1})
    value
  end

  defp frame(operation \\ "read", id \\ 1, deadline \\ 500) do
    frame =
      BridgeWireFixture.frame(operation)
      |> Map.put("id", Integer.to_string(id))
      |> Map.put("deadline_ms", Integer.to_string(deadline))

    frame =
      if operation == "write",
        do:
          frame
          |> put_in(["path", "member"], 0x4001)
          |> Map.put("payload", %{"kind" => "u16", "value" => 65_535}),
        else: frame

    BridgeWireFixture.encode(frame)
  end

  defp take(owner, id) do
    generation = BridgeWireFixture.generation()
    assert_receive {:wotex_matter_bridge_ready, ^owner, ^generation, ^id}, 1000
    assert {:ok, bytes} = Consumer.take_result(owner, id)
    result = Jason.decode!(bytes)

    assert result["id"] == Integer.to_string(id) and
             result["generation"] == Base.encode16(generation, case: :lower)

    assert result["backend"] == "matter-bridge" and result["type"] == "result" and result["v"] == 1
    assert map_size(result) == 6 and byte_size(bytes) <= 512 and String.ends_with?(bytes, "\n")
    result["outcome"]
  end

  test "read, write and invoke execute exact handlers after policy and preserve scoped Context", %{
    options: options
  } do
    owner = owner(options)

    for {native, id, operation, payload} <- [
          {"read", 1, :readproperty, nil},
          {"write", 2, :writeproperty, {:u16, 65_535}},
          {"invoke", 3, :invokeaction, {:tlv, <<21, 24>>}}
        ] do
      assert {:ok, ^id} = Consumer.submit(owner, frame(native, id), projection())
      assert_receive {:policy, request, %Context{} = context}
      assert request.id == id and request.payload == payload and request.thing == <<0, 255>>
      assert context.deadline == 1498

      assert context.request_id ==
               "matter-bridge:" <> String.duplicate("ff", 16) <> ":" <> Integer.to_string(id)

      assert context.metadata.matter_bridge.request == request
      assert context.metadata.matter_bridge.operation == operation
      assert request.principal.cats == [1, 0, 0xFFFFFFFF]
      assert request.fabric_scope.epoch == 0xFFFFFFFFFFFFFFFF
      assert_receive {:input, ^payload, ^context}
      assert_receive {:handler, ^operation, ^payload, ^context}
      assert_receive {:result, {:ok, ^payload}, ^context}
      assert take(owner, id) == "completed"
      assert {:error, %Error{code: :invalid_request}} = Consumer.take_result(owner, id)
    end
  end

  test "required policy denial, malformed returns and exceptions never reach input or handlers", %{
    options: options
  } do
    for {callback, expected} <- [
          {fn _, _ -> :deny end, "denied"},
          {fn _, _ -> true end, "failed"},
          {fn _, _ -> {:allow, :extra} end, "failed"},
          {fn _, _ -> raise "policy-private-canary" end, "failed"},
          {fn _, _ -> throw("policy-private-canary") end, "failed"},
          {fn _, _ -> exit("policy-private-canary") end, "failed"}
        ] do
      owner = owner(Keyword.put(options, :policy, callback))
      assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
      assert take(owner, 1) == expected
      refute_receive {:input, _, _}, 0
      refute_receive {:handler, _, _, _}, 0
    end
  end

  test "input and result interpretation are explicit and exception details never enter frames", %{
    options: options,
    routes: routes
  } do
    key = {<<0, 255>>, 3, 6, 0, :read}
    route = Map.fetch!(routes, key)

    for input <- [
          fn _, _ -> {:error, "input-private-canary"} end,
          fn _, _ -> raise "input-private-canary" end,
          fn _, _ -> throw("input-private-canary") end
        ] do
      owner = owner(Keyword.put(options, :routes, %{key => %{route | input: input}}))
      assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
      assert take(owner, 1) == "failed"
      assert_receive {:policy, _, _}
      refute_receive {:handler, _, _, _}, 0
    end

    for result <- [
          fn _, _ -> :unknown end,
          fn _, _ -> {:ok, :completed} end,
          fn _, _ -> raise "result-private-canary" end,
          fn _, _ -> throw("result-private-canary") end
        ] do
      owner = owner(Keyword.put(options, :routes, %{key => %{route | result: result}}))
      assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
      assert take(owner, 1) == "unknown"
      assert_receive {:policy, _, _}
      assert_receive {:input, _, _}
      assert_receive {:handler, _, _, _}
    end
  end

  test "dispatch failure retains unknown outcome without retry", %{
    options: options,
    routes: routes,
    exposed: exposed
  } do
    key = {<<0, 255>>, 3, 6, 0, :read}

    for handler <- [
          fn _, _ -> raise "dispatch-private-canary" end,
          fn _, _ -> throw("dispatch-private-canary") end,
          fn _, _ -> exit("dispatch-private-canary") end,
          fn _, _ -> Process.exit(self(), :kill) end
        ] do
      {:ok, altered} = ExposedThing.new(exposed.td, %{{:readproperty, "value"} => handler})
      owner = owner(Keyword.put(options, :routes, %{key => %{routes[key] | exposed: altered}}))
      assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
      assert take(owner, 1) == "unknown"
      assert_receive {:policy, _, _}
      assert_receive {:input, _, _}
      refute_receive {:result, _, _}, 0
    end
  end

  test "missing routes deny without invoking policy or callbacks", %{options: options} do
    owner = owner(Keyword.put(options, :routes, %{}))
    assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
    assert take(owner, 1) == "denied"
    refute_receive {:policy, _, _}, 0
    refute_receive {:handler, _, _, _}, 0
  end

  test "sixteen running or staged contexts retain credit until collected", %{options: options} do
    owner = owner(Keyword.put(options, :policy, fn _, _ -> :deny end))

    for id <- 1..16,
        do: assert({:ok, ^id} = Consumer.submit(owner, frame("read", id), projection()))

    for id <- 1..16 do
      generation = BridgeWireFixture.generation()
      assert_receive {:wotex_matter_bridge_ready, ^owner, ^generation, ^id}
    end

    assert {:error, %Error{code: :busy, details: %{}}} =
             Consumer.submit(owner, frame("read", 17), projection())

    assert {:ok, bytes} = Consumer.take_result(owner, 1)
    assert Jason.decode!(bytes)["outcome"] == "denied"
    assert {:ok, 18} = Consumer.submit(owner, frame("read", 18), projection())
    assert take(owner, 18) == "denied"
    assert {:error, %Error{code: :invalid_request}} = Consumer.take_result(owner, 1)
  end

  test "deadline expiry kills blocked handlers and retains their unknown results", %{
    options: options,
    routes: routes,
    exposed: exposed
  } do
    test = self()

    handler = fn _, _ ->
      send(test, {:running, self()})

      receive do
        :continue -> {:ok, :late}
      end
    end

    {:ok, altered} = ExposedThing.new(exposed.td, %{{:readproperty, "value"} => handler})
    key = {<<0, 255>>, 3, 6, 0, :read}
    owner = owner(Keyword.put(options, :routes, %{key => %{routes[key] | exposed: altered}}))
    assert {:ok, 1} = Consumer.submit(owner, frame("read", 1, 100), projection())
    assert_receive {:running, worker}
    monitor = Process.monitor(worker)
    assert take(owner, 1) == "unknown"
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    refute_receive {:result, _, _}, 0
  end

  test "time spent in policy, mapping or dispatch cannot extend the original deadline", %{
    options: options,
    routes: routes,
    clock: clock
  } do
    test = self()
    key = {<<0, 255>>, 3, 6, 0, :read}

    for stage <- [:policy, :input, :result] do
      Agent.update(clock, fn _ -> 1000 end)
      route = routes[key]

      policy =
        if stage == :policy,
          do: fn _, _ ->
            Agent.update(clock, fn _ -> 1498 end)
            :allow
          end,
          else: fn _, _ -> :allow end

      route =
        if stage == :input,
          do: %{
            route
            | input: fn _, _ ->
                Agent.update(clock, fn _ -> 1498 end)
                {:ok, :late}
              end
          },
          else: route

      route =
        if stage == :result,
          do: %{
            route
            | result: fn _, _ ->
                send(test, :result_entered)
                Agent.update(clock, fn _ -> 1498 end)
                :completed
              end
          },
          else: route

      configured =
        options
        |> Keyword.put(:policy, policy)
        |> Keyword.put(:routes, %{key => route})

      owner = owner(configured)

      assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
      assert take(owner, 1) == "unknown"

      if stage == :result do
        assert_receive {:handler, _, _, _}
        assert_receive :result_entered
      else
        refute_receive {:handler, _, _, _}, 0
      end

      Consumer.close(owner)
    end
  end

  test "expired or unqualified projections admit no work and cannot be retried under the same id",
       %{options: options} do
    owner = owner(options)

    assert {:error, %Error{code: :deadline_exceeded}} =
             Consumer.submit(owner, frame("read", 1, 1), projection())

    assert {:error, %Error{code: :probe_required}} =
             Consumer.submit(owner, frame("read", 2, 501), projection())

    assert {:error, %Error{code: :invalid_transport_context}} =
             Consumer.submit(owner, frame("read", 3), nil)

    assert {:error, %Error{code: :invalid_request}} = Consumer.take_result(owner, 3)
    refute_receive {:policy, _, _}, 0
    refute_receive {:handler, _, _, _}, 0
    monitor = Process.monitor(owner)

    assert {:error, %Error{code: :invalid_frame}} =
             Consumer.submit(owner, frame("read", 3), projection())

    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
  end

  test "foreign callers cannot submit, collect or sample execution time", %{options: options} do
    owner = owner(options)

    assert {:error, %Error{code: :invalid_request}} =
             Task.async(fn -> Consumer.submit(owner, frame(), projection()) end) |> Task.await()

    assert {:error, %Error{code: :invalid_request}} =
             Task.async(fn -> Consumer.take_result(owner, 1) end) |> Task.await()

    assert :elapsed = GenServer.call(owner, {:execution_clock, 1, make_ref()})
    send(owner, {make_ref(), :completed})
    send(owner, {:DOWN, make_ref(), :process, self(), :private_canary})
    send(owner, {:execution_expired, 1, make_ref()})
    assert Process.alive?(owner)
    refute_receive {:policy, _, _}, 0
  end

  test "receiver death and explicit close join active owned work", %{
    options: options,
    routes: routes,
    exposed: exposed
  } do
    test = self()

    handler = fn _, _ ->
      send(test, {:running, self()})

      receive do
        :continue -> :ok
      end
    end

    {:ok, altered} = ExposedThing.new(exposed.td, %{{:readproperty, "value"} => handler})
    key = {<<0, 255>>, 3, 6, 0, :read}

    receiver =
      spawn(fn ->
        receive do
          {:submit, owner} ->
            send(test, {:submitted, Consumer.submit(owner, frame(), projection())})

            receive do
              :finish -> :ok
            end
        end
      end)

    owner =
      owner(
        options
        |> Keyword.put(:receiver, receiver)
        |> Keyword.put(:routes, %{key => %{routes[key] | exposed: altered}})
      )

    owner_monitor = Process.monitor(owner)
    send(receiver, {:submit, owner})
    assert_receive {:submitted, {:ok, 1}}
    assert_receive {:running, worker}
    worker_monitor = Process.monitor(worker)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :normal}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}

    owner = owner(Keyword.put(options, :routes, %{key => %{routes[key] | exposed: altered}}))
    assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
    assert_receive {:running, worker}
    worker_monitor = Process.monitor(worker)
    assert :ok = Consumer.close(owner)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}
  end

  test "clock failure or regression closes admission without revealing callback text", %{
    options: options,
    clock: clock
  } do
    for value <- [999, nil, 1.0, "clock-private-canary"] do
      Agent.update(clock, fn _ -> 1000 end)
      owner = owner(options)
      monitor = Process.monitor(owner)
      Agent.update(clock, fn _ -> value end)

      assert {:error, %Error{code: :invalid_transport_context, details: %{}}} =
               Consumer.submit(owner, frame(), projection())

      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      refute_receive {:policy, _, _}, 0
    end
  end

  test "protocol corruption, duplicate and reversed ids close the scoped owner", %{options: options} do
    for corrupted <- [
          "{}\n",
          <<255, 10>>,
          frame() <> "\n",
          BridgeWireFixture.frame()
          |> Map.put("generation", String.duplicate("00", 16))
          |> BridgeWireFixture.encode()
        ] do
      owner = owner(options)
      monitor = Process.monitor(owner)

      assert {:error, %Error{code: :invalid_frame, details: %{}}} =
               Consumer.submit(owner, corrupted, projection())

      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    end

    owner = owner(Keyword.put(options, :policy, fn _, _ -> :deny end))
    assert {:ok, 2} = Consumer.submit(owner, frame("read", 2), projection())
    assert take(owner, 2) == "denied"
    monitor = Process.monitor(owner)

    assert {:error, %Error{code: :invalid_frame}} =
             Consumer.submit(owner, frame("read", 1), projection())

    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    refute_receive {:handler, _, _, _}, 0
  end

  test "configuration rejects missing policy, incompatible routes and excess identities", %{
    options: options,
    routes: routes
  } do
    key = {<<0, 255>>, 3, 6, 0, :read}
    route = routes[key]

    for invalid <- [
          nil,
          %{},
          [],
          Keyword.delete(options, :policy),
          Keyword.put(options, :policy, nil),
          Keyword.put(options, :clock, fn -> raise "clock-private-canary" end),
          Keyword.put(options, :generation, <<>>),
          [{:policy, fn _, _ -> :allow end} | options],
          Keyword.put(options, :unexpected, :private_canary)
        ] do
      assert {:error, %Error{code: :invalid_options, details: %{}}} = Consumer.start_link(invalid)
    end

    for invalid_route <- [
          nil,
          Map.delete(route, :input),
          Map.put(route, :extra, :private_canary),
          %{route | name: "missing"},
          %{route | name: <<255>>},
          %{route | operation: :invokeaction},
          %{route | exposed: %{__struct__: ExposedThing}},
          %{route | input: fn _ -> :ok end},
          %{route | result: nil}
        ] do
      assert {:error, %Error{code: :invalid_options}} =
               Consumer.start_link(Keyword.put(options, :routes, %{key => invalid_route}))
    end

    for invalid_routes <- [
          nil,
          %{{<<>>, 3, 6, 0, :read} => route},
          %{{<<1>>, 2, 6, 0, :read} => route},
          %{{<<1>>, 3, 0x8000, 0, :read} => route},
          %{key => route, {<<0, 255>>, 4, 6, 0, :read} => route},
          %{key => route, {<<1>>, 3, 6, 0, :read} => route},
          Map.new(1..17, &{{<<&1>>, &1 + 2, 6, 0, :read}, route}),
          Map.new(0..1024, &{{<<1>>, 3, 6, &1, :read}, route})
        ] do
      assert {:error, %Error{code: :invalid_options}} =
               Consumer.start_link(Keyword.put(options, :routes, invalid_routes))
    end

    assert Consumer.child_spec(options).restart == :temporary
  end

  test "slot retirement remains bounded across repeated completed requests", %{
    options: options
  } do
    owner = owner(Keyword.put(options, :policy, fn _, _ -> :deny end))

    for id <- 1..1000 do
      assert {:ok, ^id} = Consumer.submit(owner, frame("read", id), projection())
      assert take(owner, id) == "denied"
    end

    assert Consumer.format_status(%{state: :sys.get_state(owner)}).state.pending == 0
  end

  test "independent generations retain separate execution and result custody", %{options: options} do
    denied = owner(Keyword.put(options, :policy, fn _, _ -> :deny end))
    generation = :binary.copy(<<7>>, 16)
    active = owner(Keyword.put(options, :generation, generation))
    {:ok, active_projection} = ClockProjection.new(generation, 1000, 1000, 0, {1, 1})

    active_frame = fn id ->
      frame("read", id)
      |> Jason.decode!()
      |> Map.put("generation", Base.encode16(generation, case: :lower))
      |> BridgeWireFixture.encode()
    end

    assert {:ok, 1} = Consumer.submit(denied, frame(), projection())
    assert {:ok, 1} = Consumer.submit(active, active_frame.(1), active_projection)
    assert take(denied, 1) == "denied"
    assert :ok = Consumer.close(denied)
    assert_receive {:wotex_matter_bridge_ready, ^active, ^generation, 1}
    assert {:ok, bytes} = Consumer.take_result(active, 1)
    assert Jason.decode!(bytes)["outcome"] == "completed"
    assert {:ok, 2} = Consumer.submit(active, active_frame.(2), active_projection)
    assert_receive {:wotex_matter_bridge_ready, ^active, ^generation, 2}
    assert {:ok, bytes} = Consumer.take_result(active, 2)
    assert Jason.decode!(bytes)["outcome"] == "completed"
  end

  test "clock regression after policy closes all owned execution before dispatch", %{
    options: options,
    clock: clock
  } do
    test = self()

    policy = fn _, _ ->
      send(test, {:policy_worker, self()})
      Agent.update(clock, fn _ -> 999 end)
      :allow
    end

    owner = owner(Keyword.put(options, :policy, policy))
    monitor = Process.monitor(owner)
    assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
    assert_receive {:policy_worker, worker}
    worker_monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}
    refute_receive {:handler, _, _, _}, 0
    refute_receive {:wotex_matter_bridge_ready, ^owner, _, _}, 0
  end

  test "abrupt owner loss reaps handlers even when they trap exits", %{
    options: options,
    routes: routes,
    exposed: exposed
  } do
    test = self()

    handler = fn _, _ ->
      Process.flag(:trap_exit, true)
      send(test, {:trapping_worker, self()})

      receive do
        :continue -> :ok
      end
    end

    {:ok, altered} = ExposedThing.new(exposed.td, %{{:readproperty, "value"} => handler})
    key = {<<0, 255>>, 3, 6, 0, :read}
    owner = owner(Keyword.put(options, :routes, %{key => %{routes[key] | exposed: altered}}))
    assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
    assert_receive {:trapping_worker, worker}
    worker_monitor = Process.monitor(worker)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}
    refute_receive {:result, _, _}, 0
  end

  test "task-supervisor loss still reaps handlers that trap exits", %{
    options: options,
    routes: routes,
    exposed: exposed
  } do
    test = self()

    handler = fn _, _ ->
      Process.flag(:trap_exit, true)
      send(test, {:trapping_worker, self()})

      receive do
        :continue -> :ok
      end
    end

    {:ok, altered} = ExposedThing.new(exposed.td, %{{:readproperty, "value"} => handler})
    key = {<<0, 255>>, 3, 6, 0, :read}
    owner = owner(Keyword.put(options, :routes, %{key => %{routes[key] | exposed: altered}}))
    owner_monitor = Process.monitor(owner)
    assert {:ok, 1} = Consumer.submit(owner, frame(), projection())
    assert_receive {:trapping_worker, worker}
    worker_monitor = Process.monitor(worker)
    Process.exit(:sys.get_state(owner).tasks, :kill)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :normal}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}
  end

  test "closed and malformed handles return structured errors and close is idempotent", %{
    options: options
  } do
    owner = owner(options)
    assert :ok = Consumer.close(owner)
    assert :ok = Consumer.close(owner)

    assert {:error, %Error{code: :owner_closed, effect: :none}} =
             Consumer.submit(owner, frame(), projection())

    assert {:error, %Error{code: :owner_closed}} = Consumer.take_result(owner, 1)

    for invalid <- [nil, "owner", :unknown, 1] do
      assert {:error, %Error{code: :invalid_handle}} =
               Consumer.submit(invalid, frame(), projection())

      assert {:error, %Error{code: :invalid_handle}} = Consumer.take_result(invalid, 1)
      assert {:error, %Error{code: :invalid_handle}} = Consumer.close(invalid)
    end

    failing =
      spawn(fn ->
        receive do
          {:"$gen_call", _, _} -> exit(:callback_private_canary)
        end
      end)

    assert {:error, %Error{code: :owner_closed, effect: :unknown, details: %{}}} =
             Consumer.submit(failing, frame(), projection())
  end

  test "status hides native snapshots, payloads and callback configuration", %{options: options} do
    owner = owner(options)

    status =
      Consumer.format_status(%{
        state: %{pending: %{1 => :private_canary}, policy: :private_canary},
        message: :private_canary,
        reason: :private_canary,
        log: [:private_canary]
      })

    assert status == %{
             state: %{pending: 1, limit: 16},
             message: :redacted,
             reason: :redacted,
             log: []
           }

    refute inspect(:sys.get_status(owner)) =~ "root_public_key"
    refute inspect(:sys.get_status(owner)) =~ "noc_sha256"
  end
end
