defmodule WireWriteArchiveConsumerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE
  alias Wotex.BLE.{BlueZ, Error, Peer}
  @address %{service: "180f", characteristic: "2a19"}
  @accepted %{write_mode: :without_response, evidence: :native_queue_accepted}

  test "literal wire operation, bytes and evidence preserve both explicit modes" do
    {session, trace} = connect("normal")

    for bytes <- [<<>>, <<1, 2>>, :binary.copy(<<255>>, 512)] do
      assert {:ok, :written} = BLE.write(session, @address, bytes)
      assert {:ok, :written} = BLE.write(session, @address, bytes, write_mode: :with_response)
      assert {:ok, @accepted} = BLE.write(session, @address, bytes, write_mode: :without_response)
    end

    writes = Enum.filter(records(trace), &(&1["operation"] in ["write", "write_command"]))

    assert Enum.map(writes, & &1["operation"]) ==
             List.flatten(List.duplicate(["write", "write", "write_command"], 3))

    assert Enum.map(writes, & &1["parameters"]["value"]["base64"]) ==
             List.flatten(
               for bytes <- [<<>>, <<1, 2>>, :binary.copy(<<255>>, 512)],
                   do: List.duplicate(Base.encode64(bytes), 3)
             )

    assert :ok = BLE.disconnect(session)
  end

  test "invalid mode, address and value never reach the independently recorded wire" do
    {session, trace} = connect("normal")

    for options <- [
          [write_mode: nil],
          [write_mode: :auto],
          [write_mode: :without_response, write_mode: :without_response]
        ] do
      assert {:error, %Error{effect: :none}} = BLE.write(session, @address, <<1>>, options)
    end

    assert {:error, %Error{effect: :none}} =
             BLE.write(session, %{@address | service: "invalid"}, <<1>>,
               write_mode: :without_response
             )

    assert {:error, %Error{effect: :none}} =
             BLE.write(session, @address, :binary.copy(<<0>>, 513), write_mode: :without_response)

    assert Enum.map(records(trace), & &1["operation"]) |> Enum.reject(&is_nil/1) == ["open"]
  end

  test "legacy, fabricated acknowledgements and incoherent IPC cannot settle a command" do
    for mode <- ["legacy", "ack", "wrong_evidence", "extra", "wrong_id", "missing_event"] do
      {session, trace} = connect(mode)
      effect = if mode == "legacy", do: :none, else: :unknown

      assert {:error, %Error{effect: ^effect}} =
               BLE.write(session, @address, <<1>>, write_mode: :without_response)

      assert Enum.count(records(trace), &(&1["operation"] == "write_command")) == 1
      refute Enum.any?(records(trace), &(&1["operation"] == "write"))
    end
  end

  test "the original queued deadline refuses unsent work and the submitted original stays uncertain" do
    {session, trace} = connect("blocked")

    active =
      Task.async(fn ->
        BLE.write(session, @address, <<1>>, write_mode: :without_response, timeout: 600)
      end)

    eventually(fn -> Enum.any?(records(trace), &(&1["operation"] == "write_command")) end)

    assert {:error, %Error{effect: :none}} =
             BLE.write(session, @address, <<2>>, write_mode: :without_response, timeout: 20)

    assert {:error, %Error{effect: :unknown}} = Task.await(active, 2500)
    assert Enum.count(records(trace), &(&1["operation"] == "write_command")) == 1
  end

  test "separate owners preserve independent modes and owner loss retires the actual peer" do
    {first, trace} = connect("normal")
    {second, other} = connect("legacy")
    assert {:ok, @accepted} = BLE.write(first, @address, <<1>>, write_mode: :without_response)

    assert {:error, %Error{code: :not_supported}} =
             BLE.write(second, @address, <<2>>, write_mode: :without_response)

    assert {:ok, :written} = BLE.write(second, @address, <<3>>)
    assert :ok = BLE.disconnect(first)
    assert {:ok, :written} = BLE.write(second, @address, <<4>>)
    assert hd(records(trace))["pid"] != hd(records(other))["pid"]
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        {session, path} = connect("normal", false)
        send(parent, {:owned, session, path})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:owned, session, path}, 6000
    pid = hd(records(path))["pid"]
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    eventually(fn -> gone?(pid) end)

    assert {:error, %Error{effect: :none}} =
             BLE.write(session, @address, <<5>>, write_mode: :without_response)

    File.rm_rf!(Path.dirname(path))
  end

  defp connect(mode, cleanup? \\ true) do
    directory =
      Path.join(File.cwd!(), "peer-" <> Integer.to_string(System.unique_integer([:positive])))

    File.mkdir!(directory)
    executable = Path.join(directory, "peer")
    trace = Path.join(directory, "peer.trace")

    arguments = [
      System.fetch_env!("WOTEX_WRITE_ELIXIR"),
      "--erl",
      "+S 1:1 +SDcpu 1 +SDio 1",
      Path.join(File.cwd!(), "peer.exs"),
      mode,
      trace
    ]

    runtime_path = Path.dirname(System.fetch_env!("WOTEX_WRITE_ERL")) <> ":/usr/bin:/bin"

    File.write!(
      executable,
      "#!/bin/sh\nPATH=" <>
        shell_quote(runtime_path) <>
        "\nexport PATH\nexec " <> Enum.map_join(arguments, " ", &shell_quote/1) <> "\n"
    )

    File.chmod!(executable, 0o700)
    guardian = Path.join(File.cwd!(), "guardian")

    {:ok, peer} =
      Peer.new(%{adapter: "/org/bluez/hci0", address: "AA:BB:CC:DD:EE:FF", address_type: :random})

    assert {:ok, session} =
             BLE.connect(
               client: BlueZ,
               lifecycle: :persistent,
               peer: peer,
               executable: executable,
               executable_sha256: digest(executable),
               guardian: guardian,
               guardian_sha256: digest(guardian),
               bus_address: "unix:path=/unused-archive-peer",
               timeout: 5000
             )

    if cleanup? do
      on_exit(fn ->
        BLE.disconnect(session)
        eventually(fn -> gone?(hd(records(trace))["pid"]) end)
        File.rm_rf!(directory)
      end)
    end

    {session, trace}
  end

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

  defp records(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
  end

  defp gone?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
      )

    status != 0
  end

  defp eventually(fun, remaining \\ 200) do
    if fun.() do
      :ok
    else
      assert remaining > 0

      receive do
      after
        10 -> eventually(fun, remaining - 1)
      end
    end
  end
end
