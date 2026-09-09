defmodule Wotex.BLE.NativeFixture do
  @moduledoc false

  import ExUnit.{Assertions, Callbacks}
  alias Wotex.BLE.Peer

  @spec options(String.t()) :: {keyword(), String.t()}
  def options(mode \\ "normal") do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wbl-native-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    executable = Path.join(directory, "python-fixture")
    record = Path.join(directory, "calls.jsonl")
    script = Path.expand("bluez_process.py", __DIR__)

    python =
      System.find_executable("python3") || flunk("python3 is required for the native owner lane")

    File.write!(
      executable,
      "#!#{python}\nimport runpy,sys\nsys.dont_write_bytecode=True\nsys.argv=[#{Jason.encode!(script)},#{Jason.encode!(mode)},#{Jason.encode!(record)}]\nrunpy.run_path(#{Jason.encode!(script)},run_name='__main__')\n"
    )

    File.chmod!(executable, 0o700)

    on_exit(fn -> cleanup(directory, record) end)

    {:ok, peer} =
      Peer.new(%{adapter: "/org/bluez/hci0", address: "AA:BB:CC:DD:EE:FF", address_type: :random})

    {[peer: peer, executable: executable, bus_address: "unix:path=/tmp/test-bus", timeout: 5000],
     record}
  end

  defp cleanup(directory, record) do
    # A timed-out executable may not yet have reached its first Python write.
    # Keep its owned temporary directory through the startup cleanup grace.
    case recorded_process(record, 100) do
      {:ok, pid} -> eventually(fn -> process_gone?(pid) end, 150)
      :absent -> :ok
    end

    File.rm_rf!(directory)
  end

  defp recorded_process(record, attempts) do
    process = if File.exists?(record), do: Enum.find(calls(record), &Map.has_key?(&1, "pid"))

    cond do
      is_map(process) ->
        {:ok, process["pid"]}

      attempts == 0 ->
        :absent

      true ->
        Process.sleep(10)
        recorded_process(record, attempts - 1)
    end
  end

  @spec process_gone?(pos_integer()) :: boolean()
  def process_gone?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
      )

    status != 0
  end

  @spec calls(String.t()) :: [map()]
  def calls(path),
    do:
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

  @spec eventually((-> boolean()), non_neg_integer()) :: :ok
  def eventually(function, remaining \\ 100) do
    if function.() do
      :ok
    else
      assert remaining > 0
      Process.sleep(10)
      eventually(function, remaining - 1)
    end
  end
end
