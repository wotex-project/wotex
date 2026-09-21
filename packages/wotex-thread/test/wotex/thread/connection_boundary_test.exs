defmodule Wotex.Thread.ConnectionBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread
  alias Wotex.Thread.{Error, OpenThread, State, TestClient}
  alias Wotex.Thread.OpenThread.{Frame, Request, StreamOwner}

  @moduletag requirements: ["WTH-C03", "WTH-C05", "WTH-B02"], vectors: ["WTH-V04", "WTH-V10"]

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-thread-boundary-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    executable = Path.join(directory, "bridge")
    source = File.read!(Path.expand("../../fixtures/sdk_bridge.escript", __DIR__))
    escript = System.find_executable("escript") || raise "Escript is required for the injected peer"

    header =
      case System.get_env("ERL_FLAGS") do
        flags when is_binary(flags) and flags != "" -> "#!" <> escript <> "\n%%! " <> flags
        _ -> "#!" <> escript
      end

    File.write!(executable, String.replace(source, "#!/usr/bin/env escript", header))
    File.chmod!(executable, 0o700)
    File.write!(Path.join(directory, "mode"), "normal")
    on_exit(fn -> File.rm_rf!(directory) end)

    options = [
      client: OpenThread,
      executable: executable,
      executable_sha256: digest(executable),
      radio_url: "spinel+hdlc+uart:///fixture/radio",
      interface: "wthboundary",
      storage_path: Path.join(directory, "store"),
      storage_mode: :create_new,
      owner: self(),
      timeout: 5000
    ]

    %{directory: directory, options: options}
  end

  defp digest(path),
    do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  for {mode, description} <- [
        {"subscribe_bad", "a registration reply for another subscription"},
        {"stream_invalid", "a report without its value"},
        {"stream_error_unknown", "a stream error for an unknown generation"},
        {"unsubscribe_no_retire", "a cancellation reply before the retirement barrier"}
      ] do
    test "WTH-B02 #{description} closes the generation with invalid_response", context do
      mode(context, unquote(mode))
      assert {:ok, session} = Thread.connect(context.options)
      pid = session.handle.pid
      monitor = Process.monitor(pid)

      case Thread.subscribe(session, %{type: :state}) do
        {:ok, subscription} ->
          reference = subscription.reference

          if unquote(mode) == "unsubscribe_no_retire" do
            assert {:error, %Error{code: :invalid_response}} =
                     Thread.unsubscribe(session, subscription)
          else
            assert_receive {:wotex_thread, ^reference, {:error, %Error{code: :invalid_response}}},
                           3000
          end

        {:error, %Error{code: :invalid_response}} ->
          :ok
      end

      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 3000
    end
  end

  test "WTH-B02 native errors for registration and cancellation reach the caller", context do
    mode(context, "subscribe_error")
    assert {:ok, session} = Thread.connect(context.options)

    assert {:error, %Error{code: :remote_error, details: %{status: 9}}} =
             Thread.subscribe(session, %{type: :state})

    assert {:ok, %State{}} = Thread.inspect_state(session, [])
    assert :ok = Thread.disconnect(session)

    mode(context, "unsubscribe_error")
    assert {:ok, session} = Thread.connect(context.options)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state})

    assert {:error, %Error{code: :remote_error, details: %{status: 11}}} =
             Thread.unsubscribe(session, subscription)

    assert {:ok, %State{}} = Thread.inspect_state(session, [])
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 later cancellations of a closing stream wait for the same barrier", context do
    mode(context, "unsubscribe_wait")
    assert {:ok, session} = Thread.connect(context.options)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state})
    reference = subscription.reference
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, _}}

    first = Task.async(fn -> Thread.unsubscribe(session, subscription) end)
    eventually(fn -> Enum.any?(requests(context), &(&1["operation"] == "unsubscribe")) end)
    second = Task.async(fn -> Thread.unsubscribe(session, subscription) end)
    eventually(fn -> waiters(session, reference) == 1 end)
    File.write!(Path.join(context.directory, "release"), "")
    assert :ok = Task.await(first)
    assert :ok = Task.await(second)
    assert :ok = Thread.unsubscribe(session, subscription)
    assert Enum.count(requests(context), &(&1["operation"] == "unsubscribe")) == 1
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C03 full admission refuses a registration and a peer-closed error ends use",
       context do
    mode(context, "wait")
    assert {:ok, session} = Thread.connect(context.options)

    callers =
      for _ <- 1..63 do
        Task.async(fn -> OpenThread.request(session.handle, %{type: :state}, 5000) end)
      end

    eventually(fn -> map_size(:sys.get_state(session.handle.pid).pending) == 63 end)
    assert {:error, %Error{code: :busy}} = Thread.subscribe(session, %{type: :state})
    File.write!(Path.join(context.directory, "release"), "")
    for caller <- callers, do: assert({:ok, "disabled"} = Task.await(caller))
    assert :ok = Thread.disconnect(session)

    mode(context, "error_closed")
    assert {:ok, session} = Thread.connect(context.options)
    pid = session.handle.pid
    monitor = Process.monitor(pid)

    assert {:error, %Error{code: :connection_closed}} =
             OpenThread.request(session.handle, %{type: :state}, 1000)

    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 3000
  end

  test "WTH-C05 closed handles are remembered within a fixed bound", context do
    assert {:ok, session} = Thread.connect(context.options)
    connection = session.handle.pid

    subscriptions =
      for _ <- 1..1025 do
        assert {:ok, subscription} = Thread.subscribe(session, %{type: :state})
        reference = subscription.reference
        assert_receive {:wotex_thread, ^reference, {:ok, %State{}, _}}, 2000
        assert :ok = Thread.unsubscribe(session, subscription)
        subscription
      end

    state = :sys.get_state(connection)
    assert MapSet.size(state.closed) == 1024 and :queue.len(state.closed_order) == 1024
    [evicted | remembered] = subscriptions
    refute MapSet.member?(state.closed, {evicted.reference, evicted.generation})
    assert Enum.all?(remembered, &MapSet.member?(state.closed, {&1.reference, &1.generation}))
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 reports awaiting admission are delivered ahead of a native terminal", context do
    mode(context, "stream_error_late")
    assert {:ok, session} = Thread.connect(context.options)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state})
    reference = subscription.reference
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 0}}}
    [record] = Map.values(:sys.get_state(session.handle.pid).subscriptions)
    :ok = :sys.suspend(record.owner)
    File.write!(Path.join(context.directory, "release"), "")
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 4}}}, 3000
    assert_receive {:wotex_thread, ^reference, {:error, %Error{code: :queue_overflow}}}, 3000
    refute_receive {:wotex_thread, ^reference, _}, 50
    assert :ok = Thread.unsubscribe(session, subscription)
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 a full receiver loses the drained report to receiver_overflow", context do
    mode(context, "stream_error_late")
    assert {:ok, session} = Thread.connect(context.options)
    parent = self()

    receiver =
      spawn(fn ->
        receive do
          :drain -> send(parent, {:drained, drain([])})
        end
      end)

    assert {:ok, subscription} =
             Thread.subscribe(session, %{type: :state, receiver: receiver, max_queue_length: 1})

    reference = subscription.reference
    eventually(fn -> Process.info(receiver, :message_queue_len) == {:message_queue_len, 1} end)
    [record] = Map.values(:sys.get_state(session.handle.pid).subscriptions)
    :ok = :sys.suspend(record.owner)
    File.write!(Path.join(context.directory, "release"), "")
    eventually(fn -> :sys.get_state(session.handle.pid).subscriptions == %{} end)
    send(receiver, :drain)
    assert_receive {:drained, messages}, 2000

    assert [
             {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 0}}},
             {:wotex_thread, ^reference, {:error, %Error{code: :receiver_overflow}}}
           ] = messages

    assert :ok = Thread.unsubscribe(session, subscription)
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 a stream owner exit ends its live stream with owner_down", context do
    assert {:ok, session} = Thread.connect(context.options)
    connection = session.handle.pid
    observe_close(connection)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state})
    reference = subscription.reference

    # The fixture sends only the initial report, so the stream stays active until the
    # connection handles the owner's :DOWN.
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 0}}}
    [record] = Map.values(:sys.get_state(connection).subscriptions)
    Process.exit(record.owner, :kill)

    assert_receive {:wotex_thread, ^reference, {:error, %Error{code: :owner_down}}}, 2000
    assert_receive {:subscription_close, :owner_down}, 2000
    assert_receive {:subscription_close, :ok}, 2000
    refute_received {:wotex_thread, ^reference, _}
    assert :ok = Thread.unsubscribe(session, subscription)

    assert Enum.map(requests(context), & &1["operation"]) ==
             ["open", "subscribe_state", "unsubscribe"]

    assert {:ok, %State{}} = Thread.inspect_state(session, [])
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 a receiver exit after delivery cancels its live stream", context do
    assert {:ok, session} = Thread.connect(context.options)
    connection = session.handle.pid
    observe_close(connection)
    parent = self()
    receiver = spawn(fn -> forward(parent) end)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state, receiver: receiver})
    reference = subscription.reference

    # Once the only fixture report is delivered, nothing but the receiver's :DOWN can end
    # the stream; its cancellation retires the stream without a terminal delivery.
    assert_receive {:forwarded, {:wotex_thread, ^reference, {:ok, %State{}, _}}}
    Process.exit(receiver, :kill)
    assert_receive {:subscription_close, result}, 2000
    assert result == :ok
    assert :ok = Thread.unsubscribe(session, subscription)

    assert Enum.map(requests(context), & &1["operation"]) ==
             ["open", "subscribe_state", "unsubscribe"]

    assert {:ok, %State{}} = Thread.inspect_state(session, [])
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 an admission handled after its receiver exited ends the stream", context do
    mode(context, "report_on_request")
    assert {:ok, session} = Thread.connect(context.options)
    connection = session.handle.pid
    observe_close(connection)
    parent = self()
    receiver = spawn(fn -> forward(parent) end)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state, receiver: receiver})
    reference = subscription.reference
    assert_receive {:forwarded, {:wotex_thread, ^reference, {:ok, %State{}, _}}}
    [record] = Map.values(:sys.get_state(connection).subscriptions)

    # The fixture writes the next report ahead of this reply, so the suspended owner holds
    # it once the request returns.
    :ok = :sys.suspend(record.owner)
    assert {:ok, "disabled"} = OpenThread.request(session.handle, %{type: :state}, 1000)

    # The owner admits against a live receiver while the connection is suspended; the
    # receiver then exits, so its :DOWN is queued behind that admission.
    :ok = :sys.suspend(connection)
    :ok = :sys.resume(record.owner)
    _ = :sys.get_state(record.owner)
    monitor = Process.monitor(receiver)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^receiver, :killed}
    :ok = :sys.resume(connection)

    # The admission finds no receiver queue, so the stream ends before its :DOWN is handled.
    assert_receive {:subscription_close, :receiver_overflow}, 2000
    assert_receive {:subscription_close, :ok}, 2000
    assert :ok = Thread.unsubscribe(session, subscription)
    assert Enum.count(requests(context), &(&1["operation"] == "unsubscribe")) == 1
    assert {:ok, %State{}} = Thread.inspect_state(session, [])
    assert :ok = Thread.disconnect(session)
  end

  for mode <- ~w(bad_json truncated large) do
    test "WTH-C07 a #{mode} reply closes the generation before any typed result", context do
      mode(context, unquote(mode))
      assert {:ok, session} = Thread.connect(context.options)
      pid = session.handle.pid
      monitor = Process.monitor(pid)

      assert {:error, %Error{code: code}} =
               OpenThread.request(session.handle, %{type: :state}, 2000)

      assert code in [:invalid_response, :response_limit, :connection_closed]
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 3000
    end
  end

  test "WTH-C05 subscription requests are validated before contacting the owner", context do
    assert {:ok, session} = Thread.connect(context.options)
    handle = session.handle

    assert {:error, %Error{code: :invalid_subscription}} =
             OpenThread.subscribe(handle, :receiver, 10, 1000)

    assert {:error, %Error{code: :invalid_subscription}} =
             OpenThread.subscribe(handle, self(), 0, 1000)

    assert {:error, %Error{code: :invalid_handle}} = OpenThread.subscribe(:handle, self(), 1, 1000)

    assert {:ok, subscription} = OpenThread.subscribe(handle, self(), 1, 1000)

    assert {:error, %Error{code: :invalid_subscription}} =
             OpenThread.unsubscribe(handle, subscription, 0)

    assert {:error, %Error{code: :invalid_handle}} =
             OpenThread.unsubscribe(:handle, subscription, 1000)

    assert :ok = OpenThread.unsubscribe(handle, subscription, 1000)
    assert :ok = Thread.disconnect(session)

    assert {:ok, {"subscribe_state", %{queue_limit: 5}}} =
             Request.encode(%{type: :subscribe_state, queue_limit: 5})

    assert {:ok, {"unsubscribe", %{subscription_id: "s", generation: 2}}} =
             Request.encode(%{type: :unsubscribe, subscription_id: "s", generation: 2})

    assert :invalid = Frame.stream("not a frame")
  end

  test "WTH-C05 a stream owner admits by receiver capacity and follows its connection" do
    receiver = spawn(fn -> Process.sleep(:infinity) end)
    reference = make_ref()
    connection = spawn(fn -> Process.sleep(:infinity) end)
    assert {:ok, owner} = StreamOwner.start(connection, reference, receiver, 1)
    token = make_ref()

    send(owner, {:wotex_thread_report, connection, reference, 1, token})
    send(owner, :unrelated)
    :sys.get_state(owner)

    {:status, ^owner, _, items} = :sys.get_status(owner)

    keyword_items = Enum.filter(items, &Keyword.keyword?/1)
    data = Enum.flat_map(keyword_items, &Keyword.get_values(&1, :data))

    assert {~c"State", %{queue_limit: 1}} in List.flatten(data)

    send(receiver, :occupying)
    send(owner, {:wotex_thread_report, connection, reference, 2, token})
    :sys.get_state(owner)
    monitor = Process.monitor(owner)
    Process.exit(connection, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1000
    Process.exit(receiver, :kill)
  end

  test "WTH-C03 unexpected client returns are structured failures" do
    assert {:error, %Error{code: :invalid_transport_return}} =
             Thread.connect(client: TestClient, mode: :connect_invalid)

    assert {:ok, session} = Thread.connect(client: TestClient, mode: :invalid)

    assert {:error, %Error{code: :invalid_transport_return}} =
             Thread.send(session, %{type: :state})
  end

  @doc false
  @spec forward_close(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          {pid(), pid()}
        ) :: {:subscription_close, term()} | nil
  def forward_close(_, _, metadata, {parent, connection}) do
    # Subscription telemetry is global; forward only the observed connection's events.
    if self() == connection, do: send(parent, {:subscription_close, metadata.result})
  end

  defp observe_close(connection) do
    handler = "boundary-close-#{System.unique_integer([:positive])}"
    event = [:wotex, :thread, :subscription, :close]
    :ok = :telemetry.attach(handler, event, &__MODULE__.forward_close/4, {self(), connection})
    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp forward(parent) do
    receive do
      message ->
        send(parent, {:forwarded, message})
        forward(parent)
    end
  end

  defp mode(context, mode), do: File.write!(Path.join(context.directory, "mode"), mode)

  defp requests(context) do
    case File.read(Path.join(context.directory, "requests")) do
      {:ok, bytes} -> Enum.map(String.split(bytes, "\n", trim: true), &Jason.decode!/1)
      {:error, :enoent} -> []
    end
  end

  defp drain(messages) do
    receive do
      message -> drain([message | messages])
    after
      100 -> Enum.reverse(messages)
    end
  end

  defp waiters(session, reference) do
    case :sys.get_state(session.handle.pid).subscriptions do
      %{^reference => %{waiters: waiters}} -> length(waiters)
      _ -> 0
    end
  end

  defp eventually(condition, remaining \\ 300)
  defp eventually(condition, 0), do: assert(condition.())

  defp eventually(condition, remaining) do
    unless condition.() do
      Process.sleep(10)
      eventually(condition, remaining - 1)
    end
  end
end
