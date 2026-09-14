defmodule Wotex.BLE.NativeStartupTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE
  alias Wotex.BLE.{BlueZ, Error, Peer}
  alias Wotex.BLE.BlueZ.{Connection, Options}

  @root Path.expand("../../..", __DIR__)

  setup_all do
    compiler = System.find_executable("cc") || flunk("native startup tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-beam-startup-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    guardian =
      compile!(compiler, Path.join(@root, "priv/bluez/native/custody.c"), directory, "custody")

    executable =
      compile!(compiler, Path.join(@root, "test/native/beam_startup_sdk.c"), directory, "sdk")

    slow = Path.join(directory, "slow-sdk")
    {:ok, file} = File.open(slow, [:write, :binary, :raw])
    {:ok, 67_108_863} = :file.position(file, 67_108_863)
    :ok = :file.write(file, <<0>>)
    :ok = File.close(file)
    :ok = File.chmod(slow, 0o700)

    {:ok, peer} =
      Peer.new(%{
        adapter: "/org/bluez/hci0",
        address: "AA:BB:CC:DD:EE:FF",
        address_type: :random
      })

    selectors = [
      executable: executable,
      executable_sha256: digest(executable),
      guardian: guardian,
      guardian_sha256: digest(guardian)
    ]

    {:ok,
     options:
       [
         client: BlueZ,
         lifecycle: :persistent,
         peer: peer,
         connection: :borrowed,
         bus_address: "unix:path=/tmp/wotex-ble-native-test",
         timeout: 2000
       ] ++ selectors,
     marker: executable <> ".started",
     slow: slow}
  end

  test "WBL-B01 WBL-B02 BEAM verifies both artifacts before guardian-owned startup", context do
    assert {:ok, session} = BLE.connect(context.options)
    assert File.read!(context.marker) == "started\n"

    state = :sys.get_state(session.handle.pid)
    assert state.options.backend == :bluez_native
    assert state.status == :ready
    assert String.match?(state.session_generation, ~r/\A[0-9a-f]{32}\z/)

    monitor = Process.monitor(session.handle.pid)
    assert :ok = BLE.disconnect(session)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 100
  end

  test "WBL-B01 incomplete or mismatched native identity starts no process", context do
    File.rm(context.marker)

    assert {:error, %Error{code: :invalid_options}} =
             BLE.connect(Keyword.delete(context.options, :guardian_sha256))

    refute File.exists?(context.marker)

    malformed =
      Keyword.put(context.options, :executable_sha256, String.duplicate("A", 64))

    assert {:error, %Error{code: :invalid_options}} = BLE.connect(malformed)

    refute File.exists?(context.marker)

    forged = Keyword.put(context.options, :executable_sha256, String.duplicate("0", 64))

    assert {:error, %Error{code: :incompatible_backend, field: :executable}} =
             BLE.connect(forged)

    refute File.exists?(context.marker)
  end

  test "WBL-B01 owner loss interrupts in-flight artifact verification", context do
    parent = self()

    owner =
      spawn(fn ->
        receive do
          {:open, connection} ->
            send(parent, {:owner_result, GenServer.call(connection, :open, :infinity)})
        end
      end)

    connection = start_verifying!(context, owner)
    monitor = Process.monitor(connection)
    send(owner, {:open, connection})
    verifier = suspend_verifier!(connection)
    assert Process.alive?(verifier)

    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 1000
    refute_receive {:owner_result, _}
  end

  test "WBL-B01 original startup deadline interrupts artifact verification", context do
    connection = start_verifying!(context, self())
    monitor = Process.monitor(connection)
    task = Task.async(fn -> GenServer.call(connection, :open, :infinity) end)
    verifier = suspend_verifier!(connection)
    assert Process.alive?(verifier)

    send(connection, :startup_timeout)

    assert {:error, %Error{code: :timeout, field: :native_artifacts}} = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 100
  end

  test "WBL-B01 verifier failure and owner shutdown release in-flight work", context do
    connection = start_verifying!(context, self())
    monitor = Process.monitor(connection)
    task = Task.async(fn -> GenServer.call(connection, :open, :infinity) end)
    verifier = suspend_verifier!(connection)
    Process.exit(verifier, :kill)

    assert {:error, %Error{code: :transport_unavailable, field: :native_artifacts}} =
             Task.await(task)

    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 100

    connection = start_verifying!(context, self())
    caller = spawn(fn -> GenServer.call(connection, :open, :infinity) end)
    caller_monitor = Process.monitor(caller)
    verifier = suspend_verifier!(connection)
    verifier_monitor = Process.monitor(verifier)
    GenServer.stop(connection)
    assert_receive {:DOWN, ^verifier_monitor, :process, ^verifier, :killed}, 100
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, _}, 100
  end

  defp compile!(compiler, source, directory, name) do
    target = Path.join(directory, name)

    {output, status} =
      System.cmd(
        compiler,
        ["-std=c11", "-Wall", "-Wextra", "-Werror", source, "-o", target],
        cd: directory,
        env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end),
        stderr_to_stdout: true
      )

    assert status == 0, output
    target
  end

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
  end

  defp start_verifying!(context, owner) do
    options =
      context.options
      |> Keyword.drop([:client, :lifecycle])
      |> Keyword.put(:owner, owner)
      |> Keyword.put(:executable, context.slow)
      |> Keyword.put(:executable_sha256, String.duplicate("0", 64))

    assert {:ok, options} = Options.new(options)

    assert {:ok, connection} =
             GenServer.start(Connection, Map.put(options, :deadline, now() + 5000))

    connection
  end

  defp suspend_verifier!(connection, attempts \\ 100) do
    case :sys.get_state(connection) do
      %{status: :verifying, verifier_pid: pid} when is_pid(pid) ->
        true = :erlang.suspend_process(pid)
        pid

      _ when attempts > 0 ->
        Process.sleep(1)
        suspend_verifier!(connection, attempts - 1)

      state ->
        flunk("connection did not enter native verification: #{inspect(state)}")
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
