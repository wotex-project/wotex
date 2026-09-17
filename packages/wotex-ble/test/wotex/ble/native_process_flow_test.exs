defmodule Wotex.BLE.NativeProcessFlowTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE
  alias Wotex.BLE.{BlueZ, NativeProcesses, Peer}

  @root Path.expand("../../..", __DIR__)
  @grace 1000
  @fixtures @root
            |> Path.join("priv/fixtures/native-port-v1.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")
            |> Enum.filter(&(&1["operation"] == "process_flow"))

  setup_all do
    compiler = System.find_executable("c++") || flunk("process-flow tests require C++17")
    c_compiler = System.find_executable("cc") || flunk("process-flow tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-process-flow-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    guardian = Path.join(directory, "guardian")

    compile!(c_compiler, ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror"], [
      Path.join(@root, "priv/bluez/native/custody.c"),
      "-o",
      guardian
    ])

    sources =
      @fixtures
      |> Enum.map(&{&1["input"]["callback_count"], &1["input"]["value_bytes"]})
      |> Enum.uniq()
      |> Map.new(fn {callbacks, bytes} ->
        executable = Path.join(directory, "flow-source-#{callbacks}-#{bytes}")

        compile!(
          compiler,
          [
            "-std=c++17",
            "-O2",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-pedantic",
            "-DWOTEX_FLOW_CALLBACKS=#{callbacks}",
            "-DWOTEX_FLOW_VALUE_BYTES=#{bytes}",
            "-I",
            Path.join(@root, "priv/bluez/native")
          ],
          [Path.join(@root, "test/native/flow_source.cpp"), "-o", executable]
        )

        {{callbacks, bytes}, executable}
      end)

    {:ok, peer} =
      Peer.new(%{adapter: "/org/bluez/hci0", address: "AA:BB:CC:DD:EE:FF", address_type: :random})

    {:ok, guardian: guardian, sources: sources, peer: peer}
  end

  for fixture <- @fixtures do
    @fixture fixture
    test "#{fixture["id"]} bounds native report flow while the #{fixture["input"]["suspend"]} is suspended",
         context do
      input = @fixture["input"]
      assert input["callbacks_per_iteration"] == 1
      executable = context.sources[{input["callback_count"], input["value_bytes"]}]
      receiver = spawn(fn -> receiver([]) end)

      assert {:ok, session} = BLE.connect(options(context, executable))
      connection = session.handle.pid

      assert {:ok, subscription} =
               BLE.subscribe(session, %{
                 address: target(),
                 receiver: receiver,
                 max_queue_length: input["queue_limit"]
               })

      owner = subscription.pid
      port = :sys.get_state(connection).port
      {:os_pid, guardian} = Port.info(port, :os_pid)
      assert [source] = NativeProcesses.children(guardian), "the native source must be running"

      selected =
        case input["suspend"] do
          "connection" -> {:sys, connection}
          "stream_owner" -> {:sys, owner}
          "receiver" -> {:erlang, receiver}
        end

      marker = executable <> ".start"
      File.rm(marker)
      suspend(selected)
      File.write!(marker, "")
      started = now()

      samples =
        observe(
          %{connection: connection, port: port, owner: owner, receiver: receiver},
          selected,
          started + input["resume_at_ms"],
          started + input["observe_until_ms"],
          []
        )

      log = log(receiver)
      {values, after_terminal} = Enum.split_while(log, &match?({:ok, _, _}, &1))
      terminals = Enum.filter(after_terminal, &match?({:error, _}, &1))
      assert length(values) + length(after_terminal) == length(log)

      # Overload retires only the stream: the native queue or the receiver bound
      # ends it, and the session generation remains usable until explicit close.
      assert [{:error, %{code: code}}] = terminals

      # A suspended connection or stream owner withholds credit after the
      # 16-report stream window. With only the receiver suspended, credit still
      # returns, so either its queue bound or the faster native queue ends it.
      if input["suspend"] == "receiver" do
        assert length(values) <= input["queue_limit"]
        assert code in [:receiver_overflow, :queue_overflow]
      else
        assert {length(values), code} == {min(16, input["queue_limit"]), :queue_overflow}
      end

      assert Process.alive?(connection) and :sys.get_state(connection).status == :ready
      assert :sys.get_state(connection).subscriptions == %{}

      cancellation = now()
      assert :ok = BLE.disconnect(session)
      cancellation = now() - cancellation

      projection = %{
        "frame_bound" =>
          Enum.all?(
            samples,
            &(&1.frames <= 64 and &1.controls <= 320 and &1.values <= input["queue_limit"])
          ),
        "byte_bound" => Enum.all?(samples, &(&1.bytes <= 1_048_576)),
        "terminal_count" => length(terminals),
        "deliveries_after_terminal" => Enum.count(after_terminal, &match?({:ok, _, _}, &1)),
        "owned_processes_after_grace" => survivors([connection, owner], [guardian, source])
      }

      File.rm!(marker)
      Process.exit(receiver, :kill)
      assert samples != []
      assert cancellation <= @grace
      assert projection == @fixture["expectation"]["value"]
    end
  end

  defp observe(processes, selected, resume_at, until, samples) do
    current = now()

    cond do
      current >= until ->
        resume(selected)
        Enum.reverse(samples)

      current >= resume_at and selected != :resumed ->
        resume(selected)
        observe(processes, :resumed, resume_at, until, samples)

      true ->
        sample = sample(processes)
        Process.sleep(5)
        observe(processes, selected, resume_at, until, [sample | samples])
    end
  end

  defp sample(%{connection: connection, port: port, owner: owner, receiver: receiver}) do
    port_lines =
      for {^port, {:data, {:eol, line}}} <- messages(connection), do: line

    {reports, controls} = Enum.split_with(port_lines, &String.contains?(&1, ~s("report_sequence")))

    owner_reports =
      Enum.count(messages(owner), &match?({:ble_stream, _, {_, _}, {:ok, _, _}}, &1))

    %{
      frames: length(reports) + owner_reports,
      bytes: Enum.reduce(reports, 0, &(byte_size(&1) + 1 + &2)),
      controls: length(controls),
      values: Enum.count(messages(receiver), &match?({:wotex_ble, _, {:ok, _, _}}, &1))
    }
  end

  defp messages(pid) do
    case Process.info(pid, :messages) do
      {:messages, messages} -> messages
      nil -> []
    end
  end

  defp suspend({:sys, pid}), do: :sys.suspend(pid)
  defp suspend({:erlang, pid}), do: true = :erlang.suspend_process(pid)
  defp resume(:resumed), do: :ok
  defp resume({:sys, pid}), do: if(Process.alive?(pid), do: :sys.resume(pid), else: :ok)

  defp resume({:erlang, pid}),
    do: if(Process.alive?(pid), do: :erlang.resume_process(pid), else: :ok)

  defp receiver(log) do
    receive do
      {:wotex_ble, _, event} -> receiver([event | log])
      {:log, from} -> send(from, {:log, Enum.reverse(log)})
    end
  end

  defp log(receiver) do
    # Wait for every delivery already accepted by the owner before reading the log.
    Process.sleep(50)
    send(receiver, {:log, self()})
    assert_receive {:log, log}, 5000
    log
  end

  defp survivors(beam, native) do
    stop = now() + @grace

    alive = fn ->
      Enum.filter(beam, &Process.alive?/1) ++ Enum.filter(native, &NativeProcesses.alive?/1)
    end

    wait = fn wait ->
      if alive.() != [] and now() < stop do
        Process.sleep(10)
        wait.(wait)
      end
    end

    wait.(wait)
    length(alive.())
  end

  defp options(context, executable) do
    [
      client: BlueZ,
      lifecycle: :persistent,
      peer: context.peer,
      connection: :borrowed,
      bus_address: "unix:path=/tmp/wotex-ble-process-flow",
      timeout: 5000,
      executable: executable,
      executable_sha256: digest(executable),
      guardian: context.guardian,
      guardian_sha256: digest(context.guardian)
    ]
  end

  defp target do
    %{
      service: "0000180f-0000-1000-8000-00805f9b34fb",
      characteristic: "00002a19-0000-1000-8000-00805f9b34fb",
      object_path: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service0001/char0002",
      handle: 2,
      generation: 1
    }
  end

  defp compile!(compiler, flags, arguments) do
    {output, status} =
      System.cmd(compiler, flags ++ arguments,
        stderr_to_stdout: true,
        env: clean_environment()
      )

    assert status == 0, output
  end

  defp clean_environment do
    Enum.map(System.get_env(), fn
      {"PATH", value} -> {"PATH", value}
      {name, _} -> {name, nil}
    end)
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
