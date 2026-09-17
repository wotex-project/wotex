defmodule Wotex.Thread.StateSubscriptionTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread
  alias Wotex.Thread.{Error, OpenThread, Session, State, Subscription}

  @moduletag requirements: ["WTH-S06", "WTH-C05", "WTH-B02"], vectors: ["WTH-V10"]

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-thread-stream-#{System.pid()}-#{System.unique_integer([:positive])}"
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
      radio_url: "spinel+hdlc+uart:///fixture/radio",
      interface: "wthstream",
      storage_path: Path.join(directory, "store"),
      storage_mode: :create_new,
      owner: self(),
      timeout: 5000
    ]

    %{directory: directory, options: options}
  end

  test "WTH-S06 WTH-C05 the initial snapshot follows registration and credit returns after delivery",
       context do
    mode(context, "stream", 2)
    assert {:ok, session} = Thread.connect(context.options)

    assert {:ok, %Subscription{generation: 1} = subscription} =
             Thread.subscribe(session, %{type: :state})

    reference = subscription.reference
    refute inspect(subscription) =~ "Reference"

    assert_receive {:wotex_thread, ^reference, {:ok, %State{role: :disabled}, %{changed_flags: 0}}}
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 4}}}
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 4}}}
    refute_receive {:wotex_thread, ^reference, _}, 50

    # Each delivered report is acknowledged with its exact cumulative encoded bytes.
    acks = eventually_lines(context, "acks", 3)
    assert Enum.map(acks, & &1["report_sequence"]) == [1, 2, 3]
    assert Enum.all?(acks, &(&1["session_generation"] == hd(flow(context))))
    bytes = Enum.map(acks, & &1["acknowledged_bytes"])
    assert bytes == Enum.sort(bytes) and hd(bytes) > 100

    assert :ok = Thread.unsubscribe(session, subscription)
    assert :ok = Thread.unsubscribe(session, subscription)
    refute_receive {:wotex_thread, ^reference, _}, 50

    assert Enum.map(requests(context), & &1["operation"]) ==
             ["open", "subscribe_state", "unsubscribe"]

    assert :ok = Thread.disconnect(session)
    assert :ok = Thread.unsubscribe(session, subscription)
  end

  test "WTH-C05 receiver options, queue bounds and forged handles are validated before I/O",
       context do
    assert {:ok, session} = Thread.connect(context.options)
    receiver = spawn(fn -> Process.sleep(:infinity) end)

    for request <- [
          %{type: :state, extra: true},
          %{type: :state, receiver: :self},
          %{type: :state, max_queue_length: 0},
          %{type: :state, max_queue_length: 10_001},
          %{type: :state, timeout: 0},
          %{type: :event},
          nil
        ] do
      assert {:error, %Error{code: :invalid_subscription}} = Thread.subscribe(session, request)
    end

    assert {:ok, subscription} =
             Thread.subscribe(session, %{type: :state, receiver: receiver, max_queue_length: 5})

    for forged <- [
          %{subscription | generation: 2},
          %{subscription | reference: make_ref()},
          %{subscription | pid: self()},
          Map.put(subscription, :extra, true),
          nil
        ] do
      assert {:error, %Error{code: :invalid_subscription}} = Thread.unsubscribe(session, forged)
    end

    assert Enum.map(requests(context), & &1["operation"]) == ["open", "subscribe_state"]
    assert :ok = Thread.unsubscribe(session, subscription)

    other = %Session{client: Wotex.Thread.TestClient, handle: :unused, timeout: 1000}
    assert :not_supported = Thread.subscribe(other, %{type: :state})
    assert :not_supported = Thread.unsubscribe(other, subscription)
    assert :ok = Thread.disconnect(session)
    Process.exit(receiver, :kill)
  end

  test "WTH-C05 a full receiver queue terminates only that stream with receiver_overflow",
       context do
    mode(context, "stream", 3)
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

    eventually(fn -> Enum.any?(requests(context), &(&1["operation"] == "unsubscribe")) end)
    send(receiver, :drain)
    assert_receive {:drained, messages}, 2000
    reference = subscription.reference

    assert [
             {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 0}}},
             {:wotex_thread, ^reference, {:error, %Error{code: :receiver_overflow}}}
           ] = messages

    assert :ok = Thread.unsubscribe(session, subscription)
    assert {:ok, %State{}} = Thread.inspect_state(session, [])
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-B02 a native queue overflow delivers one terminal error before retirement", context do
    mode(context, "stream_error")
    assert {:ok, session} = Thread.connect(context.options)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state})
    reference = subscription.reference
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 0}}}
    assert_receive {:wotex_thread, ^reference, {:error, %Error{code: :queue_overflow}}}
    refute_receive {:wotex_thread, ^reference, _}, 50
    assert :ok = Thread.unsubscribe(session, subscription)
    assert Enum.map(requests(context), & &1["operation"]) == ["open", "subscribe_state"]
    assert {:ok, %State{}} = Thread.inspect_state(session, [])
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 receiver death cancels the native stream without delivery", context do
    assert {:ok, session} = Thread.connect(context.options)
    receiver = spawn(fn -> Process.sleep(:infinity) end)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state, receiver: receiver})
    Process.exit(receiver, :kill)
    eventually(fn -> Enum.any?(requests(context), &(&1["operation"] == "unsubscribe")) end)
    eventually(fn -> :sys.get_state(session.handle.pid).subscriptions == %{} end)
    assert :ok = Thread.unsubscribe(session, subscription)
    assert :ok = Thread.disconnect(session)
  end

  test "WTH-C05 session close sends one terminal error and removes stream owners", context do
    assert {:ok, session} = Thread.connect(context.options)
    assert {:ok, subscription} = Thread.subscribe(session, %{type: :state})
    reference = subscription.reference
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, _}}
    [record] = Map.values(:sys.get_state(session.handle.pid).subscriptions)
    owner = Process.monitor(record.owner)
    assert :ok = Thread.disconnect(session)
    assert_receive {:wotex_thread, ^reference, {:error, %Error{code: :connection_closed}}}
    assert_receive {:DOWN, ^owner, :process, _, _}
    refute_receive {:wotex_thread, ^reference, _}, 50
    assert :ok = Thread.unsubscribe(session, subscription)
  end

  for {mode, description} <- [
        {"burst", "reports beyond stream credit"},
        {"unsolicited_retire", "a barrier without cancellation or terminal error"},
        {"foreign_report", "a report for an unknown stream generation"}
      ] do
    test "WTH-B02 #{description} close the generation", context do
      mode(context, unquote(mode))
      assert {:ok, session} = Thread.connect(context.options)
      pid = session.handle.pid
      monitor = Process.monitor(pid)
      assert {:ok, subscription} = Thread.subscribe(session, %{type: :state})
      reference = subscription.reference
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 3000
      assert_receive {:wotex_thread, ^reference, {:error, %Error{code: :invalid_response}}}
    end
  end

  defp mode(context, mode, count \\ 0) do
    File.write!(Path.join(context.directory, "mode"), mode)
    File.write!(Path.join(context.directory, "report_count"), Integer.to_string(count))
  end

  defp drain(messages) do
    receive do
      message -> drain([message | messages])
    after
      100 -> Enum.reverse(messages)
    end
  end

  defp flow(context), do: context.directory |> Path.join("flow") |> File.read!() |> String.split()

  defp requests(context), do: lines(context, "requests")

  defp lines(context, name) do
    case File.read(Path.join(context.directory, name)) do
      {:ok, bytes} -> bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
      {:error, :enoent} -> []
    end
  end

  defp eventually_lines(context, name, count) do
    eventually(fn -> length(lines(context, name)) >= count end)
    lines(context, name)
  end

  defp eventually(predicate, remaining \\ 200)
  defp eventually(predicate, 0), do: assert(predicate.())

  defp eventually(predicate, remaining) do
    unless predicate.() do
      Process.sleep(10)
      eventually(predicate, remaining - 1)
    end
  end
end
