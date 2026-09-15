defmodule Wotex.Matter.SoftwareResources do
  @moduledoc false

  import ExUnit.Assertions

  @objects ~w(interaction commissioning window subscription read_client write_client
              command_sender window_opener recovery_timer)
  @sdk [
    "Packet Buffers",
    "Timers",
    "TCP endpoints",
    "UDP endpoints",
    "Exchange contexts",
    "Unsolicited message handlers",
    "Platform events"
  ]
  @environment "WOTEX_MATTER_RESOURCE_CONFIG"

  @spec with_probe(String.t(), map(), (String.t() -> term())) :: term()
  def with_probe(root, configuration \\ %{}, operation) do
    directory = Path.join(root, Base.encode16(:crypto.strong_rand_bytes(12), case: :lower))
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    path = Path.join(directory, "configuration.json")
    private_write!(path, Jason.encode!(Map.put(configuration, "directory", directory)))
    previous = System.get_env(@environment)
    System.put_env(@environment, path)

    try do
      operation.(directory)
    after
      if previous, do: System.put_env(@environment, previous), else: System.delete_env(@environment)
    end
  end

  @spec snapshot!(String.t(), integer()) :: map()
  def snapshot!(directory, deadline) do
    serial = System.unique_integer([:positive, :monotonic])
    temporary = Path.join(directory, "request-#{serial}")
    private_write!(temporary, Integer.to_string(serial))
    File.rename!(temporary, Path.join(directory, "snapshot-request"))
    value = document!(directory, "snapshot-#{serial}.json", deadline)
    assert Enum.sort(Map.keys(value)) == ~w(native open serial)
    assert value["serial"] == serial
    assert is_boolean(value["open"])
    validate!(value["native"])
    value
  end

  @spec quiescent!(String.t(), map() | nil, integer()) :: map()
  def quiescent!(directory, baseline \\ nil, timeout \\ 1_000) do
    quiescent_until!(directory, baseline, now() + timeout)
  end

  defp quiescent_until!(directory, baseline, deadline) do
    observation = snapshot!(directory, deadline)
    native = observation["native"]
    assert observation["open"]

    if balanced?(native) and (baseline == nil or native["sdk"] == baseline["sdk"]) do
      native
    else
      assert now() < deadline, "native resources did not return to baseline: #{inspect(native)}"
      Process.sleep(5)
      quiescent_until!(directory, baseline, deadline)
    end
  end

  @spec final!(String.t(), integer()) :: map()
  def final!(directory, status \\ 0) do
    value = document!(directory, "native-result.json", now() + 1_000)
    assert value["exit_status"] == status
    assert value["observer_failed"] == false

    for phase <- ~w(before after) do
      released!(value[phase])
    end

    value
  end

  @spec closed_generations!(String.t(), MapSet.t(), pos_integer()) :: {MapSet.t(), map()}
  def closed_generations!(root, previous, expected) do
    directories =
      root |> File.ls!() |> Enum.filter(&String.starts_with?(&1, "process-")) |> MapSet.new()

    added = MapSet.difference(directories, previous)
    assert MapSet.size(added) == expected

    outcomes =
      for name <- added do
        assert [_, child] = Regex.run(~r/^process-([1-9][0-9]*)$/, name)
        refute File.exists?("/proc/" <> child), "a completed native generation is still alive"
        directory = Path.join(root, name)

        if File.exists?(Path.join(directory, "startup-failure.json")) do
          failure = document!(directory, "startup-failure.json", now() + 1_000)
          assert Enum.sort(Map.keys(failure)) == ~w(code native)
          assert failure["code"] == "storage_open_failed"
          released!(failure["native"])
          if File.exists?(Path.join(directory, "native-result.json")), do: final!(directory)
          :storage_open_failed
        else
          final = final!(directory)
          assert final["after"]["objects"]["interaction"]["acquired"] == 1
          assert final["after"]["objects"]["read_client"]["acquired"] == 1
          :success
        end
      end

    {directories, Enum.frequencies(outcomes)}
  end

  @spec document!(String.t(), String.t(), integer()) :: map()
  def document!(directory, name, deadline) do
    assert now() < deadline, "native resource observation deadline elapsed: #{name}"

    case File.read(Path.join(directory, name)) do
      {:ok, bytes} ->
        value = Jason.decode!(bytes)
        assert now() < deadline, "native resource observation deadline elapsed: #{name}"
        value

      {:error, :enoent} ->
        assert now() < deadline, "native resource observation missing: #{name}"
        Process.sleep(5)
        document!(directory, name, deadline)

      {:error, reason} ->
        flunk("native resource observation unreadable: #{reason}")
    end
  end

  @spec now() :: integer()
  def now, do: System.monotonic_time(:millisecond)

  defp validate!(native) do
    assert Enum.sort(Map.keys(native)) == ~w(events objects sdk)
    assert Enum.sort(Map.keys(native["objects"])) == Enum.sort(@objects)
    assert Enum.sort(Map.keys(native["sdk"])) == Enum.sort(@sdk)

    for {_, object} <- native["objects"] do
      assert Enum.sort(Map.keys(object)) == ~w(acquired destroyed)
      assert is_integer(object["acquired"]) and object["acquired"] >= 0
      assert is_integer(object["destroyed"]) and object["destroyed"] >= 0
      assert object["destroyed"] <= object["acquired"]
    end

    for {_, count} <- Map.merge(native["sdk"], native["events"]) do
      assert is_integer(count) and count >= 0
    end
  end

  defp balanced?(native),
    do: Enum.all?(native["objects"], fn {_, value} -> value["acquired"] == value["destroyed"] end)

  defp released!(native) do
    validate!(native)
    assert balanced?(native), "native objects remain after cleanup: #{inspect(native)}"

    assert Enum.all?(native["sdk"], fn {_, count} -> count == 0 end),
           "SDK resources remain after cleanup: #{inspect(native)}"
  end

  defp private_write!(path, bytes) do
    {:ok, file} = File.open(path, [:write, :exclusive])

    try do
      File.chmod!(path, 0o600)
      :ok = IO.binwrite(file, bytes)
    after
      File.close(file)
    end
  end
end
