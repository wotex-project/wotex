defmodule Wotex.Thread.NativeOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread.{Error, OpenThread, State}

  @moduletag :software
  @moduletag requirements: ["WTH-S03", "WTH-C03", "WTH-C07"], vectors: ["WTH-V04"]

  setup do
    assert match?({:unix, :linux}, :os.type())
    executable = System.fetch_env!("WOTEX_THREAD_HOST")
    rcp = System.fetch_env!("WOTEX_THREAD_RCP")
    assert Path.type(executable) == :absolute and File.regular?(executable)
    assert Path.type(rcp) == :absolute and File.regular?(rcp)

    directory =
      Path.join(System.tmp_dir!(), "wotex-thread-sdk-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    options = [
      executable: executable,
      radio_url: "spinel+hdlc+forkpty://#{rcp}?forkpty-arg=2",
      interface: "wthbeam",
      storage_path: Path.join(directory, "settings"),
      storage_mode: :create_new,
      owner: self(),
      timeout: 5000
    ]

    %{options: options, directory: directory}
  end

  test "WTH-S03 WTH-V04 real SDK reads preserve settings across owned close and reopen", context do
    assert {:ok, handle} = OpenThread.connect(context.options)
    pids = native_pids(handle)
    assert length(pids) >= 3

    assert {:ok,
            %State{
              role: :disabled,
              network_name: "OpenThread",
              rloc16: nil,
              ipv6_enabled: false,
              thread_enabled: false,
              generation: 1
            }} =
             OpenThread.request(handle, %{type: :inspect}, 1000)

    assert {:ok, "disabled"} = OpenThread.request(handle, %{type: :state}, 1000)
    assert {:ok, "OpenThread"} = OpenThread.request(handle, %{type: :network_name}, 1000)
    assert {:ok, nil} = OpenThread.request(handle, %{type: :rloc16}, 1000)
    assert {:ok, version} = OpenThread.request(handle, %{type: :version}, 1000)
    assert version =~ "5c8c318627954c99cd1a957a290bbd4b1027d04b"
    store = Path.join(context.directory, "settings/settings.data")
    before = File.read!(store)
    assert :ok = OpenThread.disconnect(handle)
    assert_clean(handle, pids)
    assert File.read!(store) == before

    assert {:ok, reopened} =
             OpenThread.connect(Keyword.put(context.options, :storage_mode, :open_existing))

    pids = native_pids(reopened)
    assert :ok = OpenThread.disconnect(reopened)
    assert_clean(reopened, pids)
  end

  test "WTH-C03 WTH-V04 repeated acquisitions leave no interface or radio descendants", context do
    for cycle <- 1..25 do
      options =
        Keyword.put(context.options, :storage_path, Path.join(context.directory, "cycle-#{cycle}"))

      assert {:ok, handle} = OpenThread.connect(options)
      pids = native_pids(handle)
      assert {:ok, "disabled"} = OpenThread.request(handle, %{type: :state}, 1000)
      assert :ok = OpenThread.disconnect(handle)
      assert_clean(handle, pids)
    end
  end

  test "WTH-C03 WTH-V04 platform conflicts and BEAM death unwind only owned resources", context do
    assert {:ok, handle} = OpenThread.connect(context.options)
    pids = native_pids(handle)

    other_interface =
      context.options
      |> Keyword.put(:interface, "wthother")
      |> Keyword.put(:storage_mode, :open_existing)

    assert {:error, %Error{code: :storage_unavailable}} = OpenThread.connect(other_interface)

    other_store =
      Keyword.put(context.options, :storage_path, Path.join(context.directory, "conflict"))

    assert {:error, %Error{code: :interface_in_use}} = OpenThread.connect(other_store)
    assert {:ok, "disabled"} = OpenThread.request(handle, %{type: :state}, 1000)
    Process.exit(handle.pid, :kill)
    eventually(fn -> not Process.alive?(handle.pid) end)
    assert_clean(handle, pids)

    assert {:ok, reopened} =
             OpenThread.connect(Keyword.put(context.options, :storage_mode, :open_existing))

    pids = native_pids(reopened)
    assert :ok = OpenThread.disconnect(reopened)
    assert_clean(reopened, pids)
  end

  defp native_pids(handle) do
    {:os_pid, pid} = :sys.get_state(handle.pid).port |> Port.info(:os_pid)
    [pid | descendants(pid)]
  end

  defp descendants(pid) do
    case File.read("/proc/#{pid}/task/#{pid}/children") do
      {:ok, bytes} ->
        children =
          bytes
          |> String.split()
          |> Enum.map(&String.to_integer/1)

        children ++ Enum.flat_map(children, &descendants/1)

      {:error, :enoent} ->
        []
    end
  end

  defp assert_clean(handle, pids) do
    eventually(fn -> Enum.all?(pids, &(not File.exists?("/proc/#{&1}"))) end)
    refute Process.alive?(handle.pid)
    refute File.exists?("/sys/class/net/wthbeam")
    assert :ok = OpenThread.disconnect(handle)
  end

  defp eventually(condition), do: eventually(condition, System.monotonic_time(:millisecond) + 1000)

  defp eventually(condition, deadline) do
    if condition.() do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline

      receive do
      after
        5 -> eventually(condition, deadline)
      end
    end
  end
end
