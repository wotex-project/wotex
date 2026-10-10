Code.require_file("../../support/bridge_wire_fixture.ex", __DIR__)
Code.require_file("../../support/bridge_process_fixture.ex", __DIR__)

defmodule Wotex.Matter.BridgeConnectionTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.Bridge.{Connection, Consumer}
  alias Wotex.Matter.{BridgeProcessFixture, Error}
  alias Wotex.Matter.Native.ProcessCommand
  alias Wotex.Runtime.ExposedThing
  alias Wotex.ThingDescription

  @moduletag :capture_log

  setup do
    directory = BridgeProcessFixture.directory()
    on_exit(fn -> File.rm_rf!(directory) end)
    test = self()

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Bridge process fixture",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{"value" => %{"forms" => [%{"href" => "https://example.test/value"}]}},
        "actions" => %{"set" => %{"forms" => [%{"href" => "https://example.test/set"}]}}
      })

    handlers =
      Map.new(
        [{:readproperty, "value"}, {:writeproperty, "value"}, {:invokeaction, "set"}],
        fn route ->
          {route,
           fn input, context ->
             send(test, {:handler, route, input, context})
             {:ok, input}
           end}
        end
      )

    {:ok, exposed} = ExposedThing.new(td, handlers)

    routes =
      Map.new(
        [
          {:read, 0, :readproperty, "value"},
          {:write, 0x4001, :writeproperty, "value"},
          {:invoke, 0, :invokeaction, "set"}
        ],
        fn {native, member, operation, name} ->
          {{<<0, 255>>, 3, 6, member, native},
           %{
             exposed: exposed,
             operation: operation,
             name: name,
             input: fn value, _ -> {:ok, value} end,
             result: fn _, _ -> :completed end
           }}
        end
      )

    clock = start_supervised!({Agent, fn -> 1000 end})

    options = [
      owner: self(),
      arguments: [directory],
      clock: fn -> Agent.get(clock, & &1) end,
      minimum_rate: {98, 100},
      policy: fn request, context ->
        send(test, {:policy, request.id, context})
        :allow
      end,
      routes: routes,
      timeout: 1000
    ]

    %{directory: directory, options: options, clock: clock}
  end

  defp start(context, sections \\ []) do
    executable = BridgeProcessFixture.create(context.directory, sections)

    options =
      context.options ++
        [executable: executable, executable_sha256: BridgeProcessFixture.digest(executable)]

    assert {:ok, connection} = Connection.start_link(options)
    on_exit(fn -> if Process.alive?(connection), do: GenServer.stop(connection, :normal, 1500) end)
    connection
  end

  defp await_input(directory, predicate, remaining \\ 200) do
    frames = BridgeProcessFixture.input(directory)

    cond do
      predicate.(frames) ->
        frames

      remaining == 0 ->
        flunk("native input receipt absent")

      true ->
        Process.sleep(5)
        await_input(directory, predicate, remaining - 1)
    end
  end

  defp options(context, sections) do
    executable = BridgeProcessFixture.create(context.directory, sections)

    context.options ++
      [executable: executable, executable_sha256: BridgeProcessFixture.digest(executable)]
  end

  defp native_alive?(directory) do
    case File.read(Path.join(directory, "pid")) do
      {:ok, pid} ->
        {_, status} =
          ProcessCommand.run("/bin/kill", ["-0", String.trim(pid)], stderr_to_stdout: true)

        status == 0

      {:error, :enoent} ->
        false
    end
  end

  defp await_gone(directory, remaining \\ 200) do
    cond do
      not native_alive?(directory) ->
        :ok

      remaining == 0 ->
        flunk("owned native process remains alive")

      true ->
        Process.sleep(5)
        await_gone(directory, remaining - 1)
    end
  end

  defp new_context(context) do
    directory = BridgeProcessFixture.directory()
    on_exit(fn -> File.rm_rf!(directory) end)

    %{
      context
      | directory: directory,
        options: Keyword.put(context.options, :arguments, [directory])
    }
  end

  test "real Port bootstrap, policy and exact Runtime dispatch produce one native result",
       context do
    connection = start(context, before_sample: BridgeProcessFixture.request("read", 1, 600))
    assert {:ok, %{generation: generation}} = Connection.status(connection)
    assert_receive {:policy, 1, captured}
    assert_receive {:handler, {:readproperty, "value"}, nil, ^captured}
    assert captured.deadline == 1488
    assert captured.metadata.matter_bridge.request.generation == generation

    frames =
      await_input(context.directory, fn frames -> Enum.any?(frames, &(&1["type"] == "result")) end)

    results = Enum.filter(frames, &(&1["type"] == "result"))
    assert [%{"id" => "1", "outcome" => "completed", "generation" => encoded}] = results
    assert encoded == Base.encode16(generation, case: :lower)
    assert :ok = Connection.close(connection)
    assert not Process.alive?(connection)
  end

  test "missing policy/rate, malformed options and digest mismatch launch no native process",
       context do
    executable = BridgeProcessFixture.create(context.directory)

    options =
      context.options ++
        [executable: executable, executable_sha256: BridgeProcessFixture.digest(executable)]

    for invalid <- [
          Keyword.delete(options, :policy),
          Keyword.delete(options, :minimum_rate),
          Keyword.put(options, :minimum_rate, {0, 1}),
          Keyword.put(options, :arguments, [<<0>>]),
          [{:policy, fn _, _ -> :allow end} | options],
          Keyword.put(options, :timeout, 0)
        ] do
      assert {:error, %Error{code: :invalid_options, details: %{}}} = Connection.start_link(invalid)
      refute File.exists?(Path.join(context.directory, "pid"))
    end

    assert {:error, %Error{code: :incompatible_backend, field: :executable}} =
             Connection.start_link(
               Keyword.put(options, :executable_sha256, String.duplicate("0", 64))
             )

    refute File.exists?(Path.join(context.directory, "pid"))
  end

  test "environment is cleared and multiple process generations remain independent", context do
    System.put_env("WOTEX_BRIDGE_PRIVATE_CANARY", "private-environment-canary")
    on_exit(fn -> System.delete_env("WOTEX_BRIDGE_PRIVATE_CANARY") end)
    first = start(context)
    assert {:ok, %{generation: first_generation}} = Connection.status(first)
    assert File.read!(Path.join(context.directory, "environment")) == "unset\n"
    second_directory = BridgeProcessFixture.directory()
    on_exit(fn -> File.rm_rf!(second_directory) end)

    second =
      start(%{
        context
        | directory: second_directory,
          options: Keyword.put(context.options, :arguments, [second_directory])
      })

    assert {:ok, %{generation: second_generation}} = Connection.status(second)
    assert first_generation != second_generation
    assert :ok = Connection.close(first)
    assert Process.alive?(second)
    assert :ok = Connection.close(second)
  end

  test "only the explicit owner may inspect or close a supervised connection", context do
    executable = BridgeProcessFixture.create(context.directory)

    options =
      context.options ++
        [executable: executable, executable_sha256: BridgeProcessFixture.digest(executable)]

    connection = start_supervised!({Connection, options})
    assert {:ok, _} = Connection.status(connection)
    other = Task.async(fn -> {Connection.status(connection), Connection.close(connection)} end)

    assert {{:error, %Error{code: :invalid_request}}, {:error, %Error{code: :invalid_request}}} =
             Task.await(other)

    assert :ok = Connection.close(connection)
    assert %{restart: :temporary} = Connection.child_spec(options)
  end

  test "foreign ready, early exits and silent startup reap every launched child", context do
    foreign = String.replace(BridgeProcessFixture.ready(), "$generation", String.duplicate("0", 32))

    for {sections, code} <- [
          {[ready: foreign], :invalid_frame},
          {[before_ready: "exit 70"], :invalid_transport_return},
          {[before_sample: "exit 74"], :invalid_transport_return},
          {[ready: ""], :timeout},
          {[sample: ""], :timeout}
        ] do
      current = new_context(context)
      timeout = if code == :timeout, do: 100, else: 1000

      options =
        current
        |> options(sections)
        |> Keyword.put(:timeout, timeout)

      assert {:error, %Error{code: ^code, details: details}} = Connection.start_link(options)
      assert Map.keys(details) in [[], [:exit_status]]
      await_gone(current.directory)
    end

    refute_receive {:handler, _, _, _}
    refute_receive {:policy, _, _}
  end

  test "startup rejects replay, foreign generations and overflow before executing work", context do
    requests = for id <- 1..17, do: BridgeProcessFixture.request("read", id, 600)

    for frames <- [
          [
            BridgeProcessFixture.request("read", 2, 600),
            BridgeProcessFixture.request("read", 1, 600)
          ],
          [
            BridgeProcessFixture.request("read", 1, 600),
            BridgeProcessFixture.request("read", 1, 600)
          ],
          [
            BridgeProcessFixture.request("read", 1, 600, %{
              "generation" => String.duplicate("0", 32)
            })
          ],
          requests
        ] do
      current = new_context(context)

      assert {:error, %Error{code: :invalid_frame}} =
               Connection.start_link(options(current, before_sample: Enum.join(frames, "\n")))

      await_gone(current.directory)
    end

    refute_receive {:handler, _, _, _}
    refute_receive {:policy, _, _}
  end

  test "one fresh clock probe serves an ordered burst without extending native deadlines",
       context do
    requests = Enum.map_join(1..2, "\n", &BridgeProcessFixture.request("read", &1, 700))
    connection = start(context, before_sample: requests)
    assert_receive {:policy, 1, first}
    assert_receive {:policy, 2, second}
    assert first.deadline == 1488
    assert second.deadline == 1488

    frames =
      await_input(context.directory, &(Enum.count(&1, fn f -> f["type"] == "result" end) == 2))

    assert [%{"id" => "2"}] = Enum.filter(frames, &(&1["type"] == "clock-probe"))
    assert :ok = Connection.close(connection)
  end

  test "expired queued work returns unknown without policy or Runtime execution", context do
    connection = start(context, before_sample: BridgeProcessFixture.request("read", 1, 101))
    frames = await_input(context.directory, &Enum.any?(&1, fn f -> f["type"] == "result" end))
    assert [%{"id" => "1", "outcome" => "unknown"}] = Enum.filter(frames, &(&1["type"] == "result"))
    refute_receive {:policy, _, _}
    refute_receive {:handler, _, _, _}
    assert :ok = Connection.close(connection)
  end

  test "explicit policy denial writes denied exactly once", context do
    current = %{context | options: Keyword.put(context.options, :policy, fn _, _ -> :deny end)}

    request =
      BridgeProcessFixture.request("write", 1, 600, %{
        "path" => %{"endpoint" => 3, "cluster" => 6, "member" => 0x4001},
        "payload" => %{"kind" => "u16", "value" => 65_535}
      })

    connection = start(current, before_sample: request)
    frames = await_input(context.directory, &Enum.any?(&1, fn f -> f["type"] == "result" end))
    assert [%{"id" => "1", "outcome" => "denied"}] = Enum.filter(frames, &(&1["type"] == "result"))
    refute_receive {:handler, _, _, _}
    assert :ok = Connection.close(connection)
  end

  test "protocol loss closes the generation and removes the native Port", context do
    connection = start(context, after_sample: "printf '%s\\n' 'private-payload-canary'")
    monitor = Process.monitor(connection)

    assert_receive {:wotex_matter_bridge_closed, ^connection, _,
                    %Error{code: :invalid_frame, details: %{}}}

    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}
    await_gone(context.directory)
    refute_receive {:handler, _, _, _}
  end

  test "consumer loss closes the native process without an implicit restart", context do
    connection = start(context)
    %{consumer: consumer, port: port} = :sys.get_state(connection)
    assert :ok = Consumer.close(consumer)
    assert_receive {:wotex_matter_bridge_closed, ^connection, _, %Error{code: :owner_closed}}
    await_gone(context.directory)
    assert Port.info(port) == nil
  end

  test "close requires a correlated receipt and zero native exit, then joins Port release",
       context do
    foreign =
      String.replace(BridgeProcessFixture.closed(), "$generation", String.duplicate("0", 32))

    for {closing, code} <- [
          {foreign, :invalid_frame},
          {BridgeProcessFixture.closed() <> "\nexit 74", :invalid_transport_return},
          {"exit 0", :invalid_transport_return},
          {"while :; do :; done", :timeout}
        ] do
      current = new_context(context)
      connection = start(current, closing: closing)
      %{port: port} = :sys.get_state(connection)
      assert {:error, %Error{code: ^code}} = Connection.close(connection)
      assert not Process.alive?(connection)
      assert Port.info(port) == nil
      await_gone(current.directory)
    end
  end

  test "public status and crash status do not expose executable arguments or route state",
       context do
    connection = start(context)
    assert {:ok, status} = Connection.status(connection)
    assert Enum.sort(Map.keys(status)) == [:generation, :observations, :pending, :probing]
    rendered = inspect(:sys.get_status(connection), limit: :infinity)
    refute rendered =~ context.directory
    refute rendered =~ "ExposedThing"
    refute rendered =~ "minimum_rate"
    assert :ok = Connection.close(connection)
  end

  defp blocked(context, sections, operation \\ "read") do
    test = self()
    routes = Keyword.fetch!(context.options, :routes)
    {member, native} = if operation == "write", do: {0x4001, :write}, else: {0, :read}
    key = {<<0, 255>>, 3, 6, member, native}

    route =
      routes
      |> Map.fetch!(key)
      |> Map.put(:input, fn value, _ ->
        Process.flag(:trap_exit, true)
        send(test, {:owned_worker, self()})

        receive do
          :release -> {:ok, value}
        end
      end)

    current = %{
      context
      | options: Keyword.put(context.options, :routes, Map.put(routes, key, route))
    }

    connection = start(current, sections)
    assert_receive {:owned_worker, worker}, 1000
    {connection, worker, Process.monitor(worker)}
  end

  test "explicit close joins a worker that traps exits before acknowledging native closure",
       context do
    {connection, worker, monitor} =
      blocked(context, before_sample: BridgeProcessFixture.request("read", 1, 600))

    assert native_alive?(context.directory)
    assert :ok = Connection.close(connection)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    await_gone(context.directory)
    refute_receive {:handler, _, _, _}
  end

  test "explicit owner death kills trapped work and reaps the native process", context do
    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    current = %{context | options: Keyword.put(context.options, :owner, owner)}

    {connection, worker, monitor} =
      blocked(current, before_sample: BridgeProcessFixture.request("read", 1, 600))

    connection_monitor = Process.monitor(connection)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    assert_receive {:DOWN, ^connection_monitor, :process, ^connection, :normal}, 1000
    await_gone(context.directory)
    refute_receive {:handler, _, _, _}
  end

  test "native loss during admitted mutation reports unknown and kills trapped work", context do
    request =
      BridgeProcessFixture.request("write", 1, 600, %{
        "path" => %{"endpoint" => 3, "cluster" => 6, "member" => 0x4001},
        "payload" => %{"kind" => "u16", "value" => 65_535}
      })

    after_sample = request <> "\nwhile [ ! -e \"$marker/exit\" ]; do :; done\nexit 74"
    {connection, worker, monitor} = blocked(context, [after_sample: after_sample], "write")
    File.write!(Path.join(context.directory, "exit"), "")

    assert_receive {:wotex_matter_bridge_closed, ^connection, _,
                    %Error{code: :invalid_transport_return, effect: :unknown}},
                   1000

    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    await_gone(context.directory)
    refute_receive {:handler, _, _, _}
  end

  test "clock regression refuses execution and closes the generation", context do
    agent = start_supervised!({Agent, fn -> [1000, 1000, 999] end}, id: make_ref())

    clock = fn ->
      Agent.get_and_update(agent, fn [head | tail] ->
        {head, if(tail == [], do: [head], else: tail)}
      end)
    end

    current = %{context | options: Keyword.put(context.options, :clock, clock)}
    assert {:error, %Error{code: :invalid_frame}} = Connection.start_link(options(current, []))
    await_gone(context.directory)
    refute_receive {:handler, _, _, _}
  end

  test "abrupt connection death releases a cooperative native host and its trapped work", context do
    {connection, worker, monitor} =
      blocked(context, before_sample: BridgeProcessFixture.request("read", 1, 600))

    %{port: port, consumer: consumer} = :sys.get_state(connection)
    consumer_monitor = Process.monitor(consumer)
    Process.unlink(connection)
    Process.exit(connection, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1000
    assert_receive {:DOWN, ^consumer_monitor, :process, ^consumer, _}, 1000
    await_gone(context.directory)
    assert Port.info(port) == nil
    refute_receive {:handler, _, _, _}
  end

  test "close discards at most sixteen in-flight requests without executing them", context do
    for {count, expected} <- [{16, :ok}, {17, :response_limit}] do
      current = new_context(context)
      requests = Enum.map_join(1..count, "\n", &BridgeProcessFixture.request("read", &1, 600))
      connection = start(current, closing: requests <> "\n" <> BridgeProcessFixture.closed())

      case expected do
        :ok -> assert :ok = Connection.close(connection)
        code -> assert {:error, %Error{code: ^code}} = Connection.close(connection)
      end

      await_gone(current.directory)
    end

    refute_receive {:handler, _, _, _}
    refute_receive {:policy, _, _}
  end

  test "read, finite write and opaque invoke cross the process boundary with their exact payloads",
       context do
    requests = [
      BridgeProcessFixture.request("read", 1, 600),
      BridgeProcessFixture.request("write", 2, 600, %{
        "path" => %{"endpoint" => 3, "cluster" => 6, "member" => 0x4001},
        "payload" => %{"kind" => "u16", "value" => 65_535}
      }),
      BridgeProcessFixture.request("invoke", 3, 600)
    ]

    connection = start(context, before_sample: Enum.join(requests, "\n"))

    for {operation, input} <- [
          {{:readproperty, "value"}, nil},
          {{:writeproperty, "value"}, {:u16, 65_535}},
          {{:invokeaction, "set"}, {:tlv, <<21, 24>>}}
        ] do
      assert_receive {:handler, ^operation, ^input, _}, 1000
    end

    frames =
      await_input(context.directory, &(Enum.count(&1, fn f -> f["type"] == "result" end) == 3))

    assert Enum.all?(
             Enum.filter(frames, &(&1["type"] == "result")),
             &(&1["outcome"] == "completed")
           )

    assert :ok = Connection.close(connection)
  end

  test "lost, regressed and insufficient fresh samples close queued work without probe loops",
       context do
    for {next_sample, code} <- [
          {"", :timeout},
          {BridgeProcessFixture.sample(99), :invalid_frame},
          {BridgeProcessFixture.sample(100), :invalid_transport_context}
        ] do
      current = new_context(context)

      connection =
        start(current,
          after_sample: BridgeProcessFixture.request("read", 1, 700),
          next_sample: next_sample
        )

      assert_receive {:wotex_matter_bridge_closed, ^connection, _, %Error{code: ^code}}, 1000
      await_gone(current.directory)

      assert [%{"id" => "2"}] =
               Enum.filter(
                 BridgeProcessFixture.input(current.directory),
                 &(&1["type"] == "clock-probe")
               )
    end

    refute_receive {:handler, _, _, _}
    refute_receive {:policy, _, _}
  end
end
