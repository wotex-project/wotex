Code.require_file("../../support/bridge_wire_fixture.ex", __DIR__)
Code.require_file("../../support/bridge_process_fixture.ex", __DIR__)

defmodule Wotex.Matter.BridgeConnectionObservationTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter.Bridge.Connection
  alias Wotex.Matter.{BridgeProcessFixture, Error}
  @observation %{thing: <<0, 255>>, endpoint: 3, reachable: true, on_off: false, temperature: nil}

  setup do
    directory = BridgeProcessFixture.directory()
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  defp receipt(outcome) do
    BridgeProcessFixture.printf(%{
      "v" => 1,
      "backend" => "matter-bridge",
      "type" => "observation-receipt",
      "generation" => "$generation",
      "id" => "$probe",
      "outcome" => outcome
    })
  end

  defp start(context, reply, sections \\ [], overrides \\ []) do
    executable =
      BridgeProcessFixture.create(context.directory, Keyword.put(sections, :observation, reply))

    options = [
      owner: self(),
      executable: executable,
      executable_sha256: BridgeProcessFixture.digest(executable),
      arguments: [context.directory],
      clock: fn -> 1000 end,
      minimum_rate: {98, 100},
      policy: fn _, _ -> :deny end,
      routes: %{},
      timeout: 1000
    ]

    assert {:ok, connection} = Connection.start_link(Keyword.merge(options, overrides))
    on_exit(fn -> if Process.alive?(connection), do: GenServer.stop(connection, :normal, 1500) end)
    connection
  end

  defp wait_input(directory, count, remaining \\ 200) do
    frames = BridgeProcessFixture.input(directory)

    cond do
      length(frames) >= count ->
        frames

      remaining == 0 ->
        flunk("observation delivery absent")

      true ->
        Process.sleep(5)
        wait_input(directory, count, remaining - 1)
    end
  end

  test "only configured owner delivers exact state and matching applied/refused receipts",
       context do
    for outcome <- [:applied, :refused] do
      connection = start(context, receipt(Atom.to_string(outcome)))
      assert {:ok, ^outcome} = Connection.observe(connection, @observation, 1500)

      assert {:ok, %{observations: 0, pending: 0, generation: generation}} =
               Connection.status(connection)

      assert [%{"type" => "observation", "id" => "1", "thing" => "00ff", "on_off" => false} = frame] =
               wait_input(context.directory, 1)

      assert frame["generation"] == Base.encode16(generation, case: :lower)
      forbidden = Task.async(fn -> Connection.observe(connection, @observation, 1500) end)
      assert {:error, %Error{code: :invalid_request}} = Task.await(forbidden)
      assert :ok = Connection.close(connection)
      File.rm!(Path.join(context.directory, "input"))
    end
  end

  test "maximal opaque Thing frame crosses the old 512-byte transport bound", context do
    connection = start(context, receipt("applied"))

    assert {:ok, :applied} =
             Connection.observe(
               connection,
               %{@observation | thing: :binary.copy(<<255>>, 256)},
               1500
             )

    [frame] = wait_input(context.directory, 1)
    assert byte_size(Jason.encode!(frame)) > 512
    assert byte_size(frame["thing"]) == 512
    assert :ok = Connection.close(connection)
  end

  test "invalid values/deadlines preserve IDs and issue no native observation", context do
    connection = start(context, receipt("applied"))

    for {observation, deadline, expected} <- [
          {Map.delete(@observation, :on_off), 1500, :invalid_frame},
          {@observation, "1500", :invalid_frame},
          {@observation, 1000, :deadline_exceeded},
          {@observation, 1501, :invalid_timeout}
        ] do
      assert {:error, %Error{code: ^expected}} =
               Connection.observe(connection, observation, deadline)
    end

    assert BridgeProcessFixture.input(context.directory) == []
    assert {:ok, :applied} = Connection.observe(connection, @observation, 1500)
    assert [%{"id" => "1"}] = wait_input(context.directory, 1)
    assert :ok = Connection.close(connection)
  end

  test "64 unacknowledged observations retain credit until explicit joined close", context do
    connection = start(context, "")

    tags =
      for _ <- 1..64 do
        tag = make_ref()
        send(connection, {:"$gen_call", {self(), tag}, {:observe, @observation, 1500}})
        tag
      end

    assert {:error, %Error{code: :busy}} = Connection.observe(connection, @observation, 1500)
    assert {:ok, %{observations: 64, pending: 0}} = Connection.status(connection)
    frames = wait_input(context.directory, 64)
    assert Enum.map(frames, & &1["id"]) == Enum.map(1..64, &Integer.to_string/1)
    assert :ok = Connection.close(connection)

    for tag <- tags do
      assert_receive {^tag, {:error, %Error{code: :owner_closed}}}, 1000
      refute_receive {^tag, _}, 0
    end
  end

  test "full request custody leaves observation and close capacity available", context do
    test = self()

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Observation credit fixture",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{"value" => %{"forms" => [%{"href" => "https://example.test/value"}]}}
      })

    {:ok, exposed} =
      Wotex.Runtime.ExposedThing.new(td, %{
        {:readproperty, "value"} => fn _, _ ->
          send(test, {:held_read, self()})

          receive do
            :release -> {:ok, false}
          end
        end
      })

    routes = %{
      {<<0, 255>>, 3, 6, 0, :read} => %{
        exposed: exposed,
        operation: :readproperty,
        name: "value",
        input: fn nil, _ -> {:ok, nil} end,
        result: fn _, _ -> :completed end
      }
    }

    requests = Enum.map_join(1..16, "\n", &BridgeProcessFixture.request("read", &1, 600))

    connection =
      start(context, "", [before_sample: requests], routes: routes, policy: fn _, _ -> :allow end)

    workers =
      for _ <- 1..16 do
        assert_receive {:held_read, worker}, 1000
        worker
      end

    tags =
      for _ <- 1..64 do
        tag = make_ref()
        send(connection, {:"$gen_call", {self(), tag}, {:observe, @observation, 1500}})
        tag
      end

    assert {:error, %Error{code: :busy}} = Connection.observe(connection, @observation, 1500)
    assert {:ok, %{observations: 64, pending: 16}} = Connection.status(connection)
    assert :ok = Connection.close(connection)

    for tag <- tags do
      assert_receive {^tag, {:error, %Error{code: :owner_closed, effect: :none}}}, 1000
      refute_receive {^tag, _}, 0
    end

    assert Enum.all?(workers, &(not Process.alive?(&1)))
    refute Enum.any?(BridgeProcessFixture.input(context.directory), &(&1["type"] == "result"))
  end

  test "missing receipt times out and closes the generation with one pending reply", context do
    connection = start(context, "")
    monitor = Process.monitor(connection)
    assert {:error, %Error{code: :timeout}} = Connection.observe(connection, @observation, 1050)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2000
    assert_receive {:wotex_matter_bridge_closed, ^connection, _, %Error{code: :timeout}}, 1000
  end

  test "unrequested, wrong-role and foreign-generation receipts close without accepting state",
       context do
    for reply <- [
          String.replace(receipt("applied"), "observation-receipt", "result"),
          String.replace(receipt("applied"), "$generation", String.duplicate("0", 32)),
          String.replace(receipt("applied"), "'\"$probe\"'", "2")
        ] do
      connection = start(context, reply)
      monitor = Process.monitor(connection)

      assert {:error, %Error{code: :invalid_frame}} =
               Connection.observe(connection, @observation, 1500)

      assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2000

      assert_receive {:wotex_matter_bridge_closed, ^connection, _, %Error{code: :invalid_frame}},
                     1000
    end
  end

  test "explicit consumer result mapping waits for approved delivery before completed result",
       context do
    test = self()

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Observation fixture",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "value" => %{"type" => "boolean", "forms" => [%{"href" => "https://example.test/value"}]}
        }
      })

    {:ok, exposed} =
      Wotex.Runtime.ExposedThing.new(td, %{
        {:readproperty, "value"} => fn _, context ->
          send(test, {:read_handler, context})
          {:ok, false}
        end
      })

    routes = %{
      {<<0, 255>>, 3, 6, 0, :read} => %{
        exposed: exposed,
        operation: :readproperty,
        name: "value",
        input: fn nil, _ -> {:ok, nil} end,
        result: fn {:ok, false}, context ->
          send(test, {:approved_delivery, self(), context})

          receive do
            :applied -> :completed
            :refused -> :failed
          after
            500 -> :unknown
          end
        end
      }
    }

    policy = fn request, context ->
      send(test, {:approved_policy, request.id, context})
      :allow
    end

    connection =
      start(
        context,
        receipt("applied"),
        [before_sample: BridgeProcessFixture.request("read", 1, 600)],
        routes: routes,
        policy: policy
      )

    assert_receive {:approved_policy, 1, captured}, 1000
    assert_receive {:read_handler, ^captured}, 1000
    assert_receive {:approved_delivery, mapper, ^captured}, 1000
    refute Enum.any?(BridgeProcessFixture.input(context.directory), &(&1["type"] == "result"))
    assert {:ok, :applied} = Connection.observe(connection, @observation, captured.deadline)
    send(mapper, :applied)
    frames = wait_input(context.directory, 2)

    assert [
             %{"type" => "observation", "id" => "1"},
             %{"type" => "result", "id" => "1", "outcome" => "completed"}
           ] = frames

    assert :ok = Connection.close(connection)
  end

  test "receipt replay closes a generation after its one accepted acknowledgment", context do
    connection = start(context, receipt("applied") <> "\n" <> receipt("applied"))
    monitor = Process.monitor(connection)
    assert {:ok, :applied} = Connection.observe(connection, @observation, 1500)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2000
    assert_receive {:wotex_matter_bridge_closed, ^connection, _, %Error{code: :invalid_frame}}, 1000
  end

  test "known queued receipt during close cannot revive its canceled caller", context do
    closing = receipt("applied") <> "\n" <> BridgeProcessFixture.closed()
    connection = start(context, "", closing: closing)
    tag = make_ref()
    send(connection, {:"$gen_call", {self(), tag}, {:observe, @observation, 1500}})
    assert {:ok, %{observations: 1}} = Connection.status(connection)
    assert :ok = Connection.close(connection)
    assert_receive {^tag, {:error, %Error{code: :owner_closed}}}, 1000
    refute_receive {^tag, _}, 0
  end

  test "observation clock regression preserves conservative mutation loss", context do
    clock = start_supervised!({Agent, fn -> 1000 end})

    connection =
      start(
        context,
        receipt("applied"),
        [before_sample: BridgeProcessFixture.request("invoke", 1, 600)],
        clock: fn -> Agent.get(clock, & &1) end
      )

    assert {:ok, :applied} = Connection.observe(connection, @observation, 1500)
    Agent.update(clock, fn _ -> 999 end)

    assert {:error, %Error{code: :invalid_transport_context, effect: :unknown}} =
             Connection.observe(connection, @observation, 1500)

    assert_receive {:wotex_matter_bridge_closed, ^connection, _,
                    %Error{code: :invalid_transport_context, effect: :unknown}},
                   2000
  end

  test "configured owner loss retires pending delivery and joins its native process", context do
    owner =
      spawn(fn ->
        receive do
          {:observe, connection} -> Connection.observe(connection, @observation, 1500)
        end
      end)

    connection = start(context, "", [], owner: owner)
    monitor = Process.monitor(connection)
    send(owner, {:observe, connection})
    assert [%{"type" => "observation"}] = wait_input(context.directory, 1)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2000
    assert {:error, %Error{code: :owner_closed}} = Connection.status(connection)
    pid = File.read!(Path.join(context.directory, "pid")) |> String.trim()

    {_, status} =
      Wotex.Matter.Native.ProcessCommand.run("/bin/kill", ["-0", pid], stderr_to_stdout: true)

    assert status != 0
  end

  test "admission time cannot extend an observation deadline or consume its ID", context do
    clock = start_supervised!({Agent, fn -> false end})

    connection =
      start(context, receipt("applied"), [],
        clock: fn ->
          if Agent.get(clock, & &1), do: Process.sleep(35)
          1000
        end
      )

    Agent.update(clock, fn _ -> true end)

    assert {:error, %Error{code: :deadline_exceeded}} =
             Connection.observe(connection, @observation, 1020)

    assert BridgeProcessFixture.input(context.directory) == []
    Agent.update(clock, fn _ -> false end)
    assert {:ok, :applied} = Connection.observe(connection, @observation, 1500)
    assert [%{"id" => "1"}] = wait_input(context.directory, 1)
    assert :ok = Connection.close(connection)
  end

  test "native loss during delivery replies once and preserves prior mutation uncertainty",
       context do
    connection =
      start(context, "exit 74", before_sample: BridgeProcessFixture.request("invoke", 1, 600))

    monitor = Process.monitor(connection)

    assert {:error, %Error{code: :invalid_transport_return, effect: :unknown} = error} =
             Connection.observe(connection, @observation, 1500)

    assert error.details == %{exit_status: 74}

    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2000

    assert_receive {:wotex_matter_bridge_closed, ^connection, _,
                    %Error{code: :invalid_transport_return, effect: :unknown}},
                   1000

    assert {:error, %Error{code: :owner_closed}} = Connection.status(connection)
  end

  test "receipt clock sampling preserves the original real deadline", context do
    clock = start_supervised!({Agent, fn -> nil end})

    connection =
      start(context, receipt("applied"), [],
        clock: fn ->
          phase =
            Agent.get_and_update(clock, fn
              nil -> {nil, nil}
              count -> {count, count + 1}
            end)

          if phase == 1, do: Process.sleep(400)
          1000
        end
      )

    Agent.update(clock, fn _ -> 0 end)
    monitor = Process.monitor(connection)

    assert {:error, %Error{code: :invalid_frame}} =
             Connection.observe(connection, @observation, 1300)

    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2000
    assert_receive {:wotex_matter_bridge_closed, ^connection, _, %Error{code: :invalid_frame}}, 1000
  end

  test "collected observations release credit without reusing their identities", context do
    connection = start(context, receipt("refused"))

    for _ <- 1..65 do
      assert {:ok, :refused} = Connection.observe(connection, @observation, 1500)
    end

    assert {:ok, %{observations: 0}} = Connection.status(connection)
    frames = wait_input(context.directory, 65)
    assert Enum.map(frames, & &1["id"]) == Enum.map(1..65, &Integer.to_string/1)
    assert :ok = Connection.close(connection)
  end

  test "observation identity exhaustion closes instead of wrapping", context do
    connection = start(context, receipt("applied"))
    maximum = 0xFFFFFFFFFFFFFFFF
    :sys.replace_state(connection, &%{&1 | last_observation_id: maximum - 1})

    assert {:ok, :applied} = Connection.observe(connection, @observation, 1500)
    assert [%{"id" => id}] = wait_input(context.directory, 1)
    assert id == Integer.to_string(maximum)
    monitor = Process.monitor(connection)

    assert {:error, %Error{code: :response_limit}} =
             Connection.observe(connection, @observation, 1500)

    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2000

    assert_receive {:wotex_matter_bridge_closed, ^connection, _, %Error{code: :response_limit}},
                   1000

    assert length(BridgeProcessFixture.input(context.directory)) == 1
  end

  test "invalid receipt clocks close with fixed errors and no callback text", context do
    for value <- [999, nil, :raised, :thrown] do
      clock = start_supervised!({Agent, fn -> nil end}, id: make_ref())

      connection =
        start(context, receipt("applied"), [],
          clock: fn ->
            phase =
              Agent.get_and_update(clock, fn
                nil -> {nil, nil}
                count -> {count, count + 1}
              end)

            case {phase, value} do
              {1, :raised} -> raise "private clock details"
              {1, :thrown} -> throw("private clock details")
              {1, result} -> result
              _ -> 1000
            end
          end
        )

      Agent.update(clock, fn _ -> 0 end)

      assert {:error, %Error{code: :invalid_transport_context, details: %{}}} =
               Connection.observe(connection, @observation, 1500)

      assert_receive {:wotex_matter_bridge_closed, ^connection, _,
                      %Error{code: :invalid_transport_context, details: %{}}},
                     2000
    end
  end

  test "a receipt at the supplied deadline cannot approve state", context do
    clock = start_supervised!({Agent, fn -> nil end})

    connection =
      start(context, receipt("applied"), [],
        clock: fn ->
          Agent.get_and_update(clock, fn
            nil -> {1000, nil}
            0 -> {1000, 1}
            _ -> {1300, 2}
          end)
        end
      )

    Agent.update(clock, fn _ -> 0 end)

    assert {:error, %Error{code: :invalid_frame}} =
             Connection.observe(connection, @observation, 1300)

    assert_receive {:wotex_matter_bridge_closed, ^connection, _, %Error{code: :invalid_frame}}, 2000
  end
end
