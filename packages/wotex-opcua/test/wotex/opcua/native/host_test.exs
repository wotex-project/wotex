defmodule Wotex.OPCUA.Native.HostTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.OPCUA.{Error, Native.Host, Native.Ready}

  setup_all do
    directory =
      Path.join(System.tmp_dir!(), "wotex-opcua-native-host-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    compiler =
      System.find_executable("cc") || flunk("native bootstrap tests require a C11 compiler")

    root = Path.expand("../../../..", __DIR__)

    for {source, output} <- [
          {"priv/native/custody.c", "guardian"},
          {"test/native/host_probe.c", "probe"}
        ] do
      {diagnostic, status} =
        System.cmd(
          compiler,
          [
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            Path.join(root, source),
            "-o",
            Path.join(directory, output)
          ],
          stderr_to_stdout: true,
          env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
        )

      assert status == 0, diagnostic
    end

    slow_guardian = Path.join(directory, "slow-hash-guardian")
    {:ok, file} = File.open(slow_guardian, [:write, :binary, :raw])
    {:ok, _} = :file.position(file, 268_435_455)
    :ok = :file.write(file, <<0>>)
    File.close(file)
    File.chmod!(slow_guardian, 0o700)
    block = :binary.copy(<<0>>, 65_536)

    slow_digest =
      1..4096
      |> Enum.reduce(:crypto.hash_init(:sha256), fn _, hash -> :crypto.hash_update(hash, block) end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    %{
      directory: directory,
      guardian: Path.join(directory, "guardian"),
      slow_guardian: slow_guardian,
      slow_digest: slow_digest
    }
  end

  test "WOP-X01 verified readiness includes an independently captured owner clock", context do
    previous = System.get_env("WOTEX_PRIVATE_SENTINEL")
    System.put_env("WOTEX_PRIVATE_SENTINEL", "private-bootstrap-canary")

    on_exit(fn ->
      if previous,
        do: System.put_env("WOTEX_PRIVATE_SENTINEL", previous),
        else: System.delete_env("WOTEX_PRIVATE_SENTINEL")
    end)

    {options, directory} = fixture(context, "valid")
    before = System.monotonic_time(:millisecond)

    assert {:ok, host, %{ready: %Ready{clock_ms: native}, received_at_ms: received}} =
             Host.start_link(options)

    assert native >= 0
    assert received >= before and received <= System.monotonic_time(:millisecond)
    assert Process.alive?(host)
    assert host in elem(Process.info(self(), :links), 1)
    assert File.read!(Path.join(directory, "environment")) == "private=0\nlocale=C\n"
    GenServer.stop(host, :normal)
    assert_native_reaped(directory)
  end

  test "WOP-X04 owner correlates open/close and replenishes only consumed output", context do
    {options, directory} = fixture(context, "session_reply")
    assert {:ok, host, _} = Host.start_link(options)

    assert {:ok, %{"session_timeout_ms" => 60_000.0, "namespace_array" => namespaces}} =
             Host.request(host, "open", %{"session_timeout_ms" => 60_000}, 1000)

    assert namespaces == ["http://opcfoundation.org/UA/", "urn:fixture"]
    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert_native_reaped(directory)
  end

  test "WOP-X03 fragmented readiness is accumulated without changing its deadline", context do
    {options, directory} = fixture(context, "fragmented")
    assert {:ok, host, %{ready: %Ready{}}} = Host.start_link(options)
    GenServer.stop(host, :normal)
    assert_native_reaped(directory)
  end

  test "WOP-X01 malformed configuration and either digest mismatch starts no SDK", context do
    {options, directory} = fixture(context, "valid")

    for invalid <- [[{:unknown, true} | options], [{:timeout, 0} | options]] do
      assert {:error, %Error{code: :invalid_native_configuration}} = Host.start_link(invalid)
    end

    for field <- [:guardian_digest, :executable_digest] do
      assert {:error, %Error{code: :invalid_native_executable}} =
               Host.start_link(Keyword.put(options, field, String.duplicate("0", 64)))
    end

    refute File.exists?(Path.join(directory, "host.pid"))
  end

  test "WOP-X01 an admitted file that the operating system cannot execute fails safely", context do
    {options, directory} = fixture(context, "valid")
    invalid = Path.join(directory, "not-an-executable-format")
    File.write!(invalid, <<0, 1, 2, 3>>)
    File.chmod!(invalid, 0o700)
    options = Keyword.merge(options, guardian: invalid, guardian_digest: digest(invalid))

    assert {:error, %Error{code: :native_process_terminated, details: %{exit_status: 8}}} =
             Host.start_link(options)

    refute File.exists?(Path.join(directory, "host.pid"))
  end

  test "WOP-X01 foreign and replayed claims cannot acquire an existing host", context do
    {options, directory} = fixture(context, "valid")
    assert {:ok, host, _} = Host.start_link(options)

    for request <- [{Host, :claim, make_ref()}, :unknown] do
      assert {:error, %Error{code: :invalid_native_handle}} = GenServer.call(host, request)
    end

    assert {:error, %Error{code: :invalid_native_frame}} = Host.request(host, "read", %{}, 0)

    parent = self()

    spawn(fn ->
      send(parent, {:foreign_claim, GenServer.call(host, {Host, :claim, make_ref()})})
      send(parent, {:foreign_request, Host.request(host, "read", %{}, 1000)})
    end)

    assert_receive {:foreign_claim, {:error, %Error{code: :invalid_native_handle}}}
    assert_receive {:foreign_request, {:error, %Error{code: :invalid_native_handle}}}
    assert Process.alive?(host)
    GenServer.stop(host, :normal)
    assert_native_reaped(directory)
  end

  test "WOP-X07 a blocked hash worker cannot extend startup or survive its owner", context do
    for fault <- [:deadline, :owner_death, :worker_death] do
      {options, directory} = fixture(context, "valid")

      options =
        Keyword.merge(options,
          guardian: context.slow_guardian,
          guardian_digest: context.slow_digest,
          timeout: 300
        )

      {owner, host, worker} = blocked_hash_owner(options)
      host_monitor = Process.monitor(host)
      worker_monitor = Process.monitor(worker)

      case fault do
        :owner_death ->
          Process.exit(owner, :kill)

        :worker_death ->
          Process.exit(worker, :kill)

          assert_receive {:hash_result, ^owner, {:error, %Error{code: :invalid_native_executable}}},
                         1000

          send(owner, :finish)

        :deadline ->
          assert_receive {:hash_result, ^owner, {:error, %Error{code: :deadline_exceeded}}}, 1000
          send(owner, :finish)
      end

      assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}, 1000
      assert_receive {:DOWN, ^host_monitor, :process, ^host, _}, 1000
      refute File.exists?(Path.join(directory, "host.pid"))
    end
  end

  test "WOP-X01 malformed, oversized and duplicate ready frames unwind without killing caller",
       context do
    assert Process.info(self(), :trap_exit) == {:trap_exit, false}

    for mode <- ["invalid", "overlong", "duplicate"] do
      {options, directory} = fixture(context, mode)
      assert {:error, %Error{code: :invalid_native_ready}} = Host.start_link(options)
      assert_native_reaped(directory)
    end
  end

  test "WOP-X01 executable exit and contained SDK stderr are bounded startup failures", context do
    for {mode, status} <- [{"exit", 17}, {"stderr", 131}] do
      {options, directory} = fixture(context, mode)

      assert {:error,
              %Error{code: :native_process_terminated, details: %{exit_status: ^status}} = error} =
               Host.start_link(options)

      refute inspect(error) =~ "private SDK diagnostic"
      assert_native_reaped(directory)
    end
  end

  test "WOP-X07 a stopped SDK is independently reaped after the absolute startup deadline",
       context do
    {options, directory} = fixture(context, "stopped")
    began = System.monotonic_time(:millisecond)

    assert {:error, %Error{code: :deadline_exceeded}} =
             Host.start_link(Keyword.put(options, :timeout, 1000))

    assert System.monotonic_time(:millisecond) - began < 1500
    assert_native_reaped(directory)
  end

  test "WOP-X07 owner death interrupts pending readiness and ends only its SDK", context do
    {options, directory} = fixture(context, "stopped")
    owner = spawn(fn -> Host.start_link(options) end)
    monitor = Process.monitor(owner)
    assert eventually(fn -> File.regular?(Path.join(directory, "host.pid")) end)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert_native_reaped(directory)
  end

  test "WOP-X07 owner death after readiness closes the owned native process", context do
    {options, directory} = fixture(context, "valid")
    parent = self()

    owner =
      spawn(fn ->
        result = Host.start_link(options)
        send(parent, {:opened, result})

        receive do
          :finish -> :ok
        end
      end)

    monitor = Process.monitor(owner)
    assert_receive {:opened, {:ok, host, _}}, 3000
    host_monitor = Process.monitor(host)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert_receive {:DOWN, ^host_monitor, :process, ^host, _}, 1000
    assert_native_reaped(directory)
  end

  test "WOP-X07 owner monitoring survives an explicitly removed owner link", context do
    {options, directory} = fixture(context, "valid")
    parent = self()

    owner =
      spawn(fn ->
        {:ok, host, _} = Host.start_link(options)
        Process.unlink(host)
        send(parent, {:unlinked, host})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:unlinked, host}, 3000
    monitor = Process.monitor(host)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    assert_native_reaped(directory)
  end

  test "WOP-X07 a suspended claimant cannot retain an unclaimed ready SDK", context do
    {options, directory} = fixture(context, "valid")
    options = Keyword.put(options, :timeout, 1000)
    parent = self()

    owner =
      spawn(fn ->
        receive do
          :begin -> send(parent, {:unclaimed_result, Host.start_link(options)})
        end
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    :erlang.trace(owner, true, [:procs])
    send(owner, :begin)
    assert_receive {:trace, ^owner, :spawn, host, _}, 1000
    assert :erlang.suspend_process(owner)
    :erlang.trace(owner, false, [:all])
    monitor = Process.monitor(host)
    assert eventually(fn -> File.regular?(Path.join(directory, "host.pid")) end)
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1500
    assert_native_reaped(directory)
    assert :erlang.resume_process(owner)
    assert_receive {:unclaimed_result, {:error, %Error{code: :native_startup_failed}}}, 1000
  end

  test "WOP-X03 second readiness and post-bootstrap exit terminate once", context do
    for {mode, code} <- [{"late", :invalid_native_frame}, {"late_exit", :native_process_terminated}] do
      {options, directory} = fixture(context, mode)
      assert {:ok, host, _} = Host.start_link(options)
      monitor = Process.monitor(host)
      File.write!(Path.join(directory, "trigger"), "go")
      assert_receive {:wotex_opcua_native, ^host, {:error, %Error{code: ^code}}}, 1000
      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
      refute_receive {:wotex_opcua_native, ^host, _}
      assert_native_reaped(directory)
    end
  end

  test "WOP-X03 a native peer stalled after request cannot extend the owner deadline", context do
    {options, directory} = fixture(context, "stall_request")
    assert {:ok, host, _} = Host.start_link(options)
    monitor = Process.monitor(host)

    assert {:error, %Error{code: :deadline_exceeded, field: :request}} =
             Host.request(host, "read", %{}, 100)

    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    refute_receive {:wotex_opcua_native, ^host, _}
    assert_native_reaped(directory)
  end

  test "WOP-X04 an unacknowledged Write retains unknown effect after owner timeout", context do
    {options, directory} = fixture(context, "stall_request")
    assert {:ok, host, _} = Host.start_link(options)
    monitor = Process.monitor(host)

    assert {:error, %Error{code: :deadline_exceeded, field: :request, effect: :unknown}} =
             Host.request(host, "write", %{}, 100)

    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    assert_native_reaped(directory)
  end

  test "WOP-X07 lost Port ownership produces one terminal error and native cleanup", context do
    {options, directory} = fixture(context, "valid")
    assert {:ok, host, _} = Host.start_link(options)
    monitor = Process.monitor(host)

    [port] =
      host
      |> Process.info(:links)
      |> elem(1)
      |> Enum.filter(&is_port/1)

    assert Port.close(port)
    assert_receive {:wotex_opcua_native, ^host, {:error, %Error{code: :native_process_terminated}}}
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}
    refute_receive {:wotex_opcua_native, ^host, _}
    assert_native_reaped(directory)
  end

  @tag capture_log: true
  test "WOP-X01 temporary child specification does not reconnect after loss", context do
    {options, directory} = fixture(context, "valid")
    assert %{restart: :temporary, shutdown: 1000} = Host.child_spec(options)
    {:ok, supervisor} = Supervisor.start_link([{Host, options}], strategy: :one_for_one)
    [{Host, host, :worker, [Host]}] = Supervisor.which_children(supervisor)
    Process.exit(host, :kill)
    assert eventually(fn -> Supervisor.which_children(supervisor) == [] end)
    assert_native_reaped(directory)
    Supervisor.stop(supervisor)
  end

  defp fixture(context, mode) do
    directory = Path.join(context.directory, "#{mode}-#{System.unique_integer([:positive])}")
    File.mkdir!(directory)
    executable = Path.join(directory, mode)
    File.cp!(Path.join(context.directory, "probe"), executable)
    File.chmod!(executable, 0o700)

    options = [
      executable: executable,
      executable_digest: digest(executable),
      guardian: context.guardian,
      guardian_digest: digest(context.guardian),
      timeout: 2000
    ]

    {options, directory}
  end

  defp blocked_hash_owner(options) do
    parent = self()

    owner =
      spawn(fn ->
        receive do
          :begin -> send(parent, {:hash_result, self(), Host.start_link(options)})
        end

        receive do
          :finish -> :ok
        end
      end)

    :erlang.trace(owner, true, [:procs, :set_on_spawn])
    send(owner, :begin)
    assert_receive {:trace, ^owner, :spawn, host, _}, 1000
    assert_receive {:trace, ^host, :spawn, worker, _}, 1000
    assert :erlang.suspend_process(worker)

    on_exit(fn ->
      for pid <- [worker, host, owner] do
        if Process.alive?(pid) do
          try do
            :erlang.trace(pid, false, [:all])
          rescue
            ArgumentError -> :ok
          end

          Process.exit(pid, :kill)
        end
      end
    end)

    {owner, host, worker}
  end

  defp assert_native_reaped(directory) do
    file = Path.join(directory, "host.pid")
    assert File.regular?(file)
    pids = File.read!(file) |> String.split()
    assert length(pids) == 2
    began = System.monotonic_time(:millisecond)

    assert eventually(fn ->
             Enum.all?(pids, fn pid ->
               {_, status} =
                 System.cmd("/bin/kill", ["-0", pid],
                   stderr_to_stdout: true,
                   env: [{"LC_ALL", "C"}]
                 )

               status != 0
             end)
           end)

    assert System.monotonic_time(:millisecond) - began <= 500
  end

  defp eventually(check, attempts \\ 100)
  defp eventually(_, 0), do: false

  defp eventually(check, attempts) do
    if check.(),
      do: true,
      else:
        (
          Process.sleep(5)
          eventually(check, attempts - 1)
        )
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
