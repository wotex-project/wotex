defmodule Wotex.BLE.NativeFixture do
  @moduledoc false

  # Launches the scripted native protocol peer through the production guardian.
  # Its replies are scripted inputs: these options prove BEAM connection, stream
  # owner and Runtime adapter contracts, never BlueZ or D-Bus behavior.

  import ExUnit.{Assertions, Callbacks}
  alias Wotex.BLE.Peer

  @root Path.expand("../..", __DIR__)
  @artifacts {__MODULE__, :artifacts}
  @notify ["read", "notify"]
  @procedure ["read", "write"]
  @stream %{
    "flags" => @notify,
    "early" => [<<1, 0>>],
    "read_reports" => 2,
    "value" => <<0x34, 0x12>>
  }
  @runtime %{"flags" => @notify, "characteristics" => 1, "early" => [<<1, 0>>]}
  @scenarios %{
    "normal" => %{},
    "wrong_ready" => %{"modes" => ["wrong_ready"]},
    "silent" => %{"modes" => ["silent"]},
    "oversize" => %{"modes" => ["oversize"]},
    "truncated" => %{"modes" => ["truncated"]},
    "uncooperative" => %{"modes" => ["uncooperative"]},
    "close_slow" => %{"modes" => ["close_slow"]},
    "close_drain" => %{"modes" => ["close_drain"]},
    "startup_error" => %{"modes" => ["open_error"], "error" => %{"code" => "disconnected"}},
    "blocked" => %{"modes" => ["discover_blocked"]},
    "slow" => %{"modes" => ["discover_slow"]},
    "remote_error" => %{"modes" => ["discover_error"], "error" => %{"code" => "not_permitted"}},
    "timeout_error" => %{"modes" => ["discover_error"], "error" => %{"code" => "timeout"}},
    "invalid_frame" => %{"modes" => ["discover_invalid_frame"]},
    "wrong_id" => %{"modes" => ["discover_wrong_id"]},
    "health_missing" => %{"modes" => ["health_error"], "error" => %{"code" => "invalid_response"}},
    "health_wrong_peer" => %{"modes" => ["health_error"], "error" => %{"code" => "peer_changed"}},
    "health_disconnected" => %{"modes" => ["health_error"], "error" => %{"code" => "disconnected"}},
    "health_timeout" => %{"modes" => ["health_blocked"]},
    "pair" => %{"challenge" => %{"kind" => "confirm_passkey", "value" => 123_456}},
    "pair_pin" => %{"challenge" => %{"kind" => "request_pin", "value" => nil}},
    "pair_passkey" => %{"challenge" => %{"kind" => "request_passkey", "value" => nil}},
    "procedure" => %{"flags" => @procedure},
    "procedure_runtime" => %{"flags" => @procedure, "characteristics" => 1},
    "procedure_command_only" => %{"flags" => ["write-without-response"]},
    "procedure_timeout" => %{"flags" => @procedure, "modes" => ["procedure_blocked"]},
    "procedure_crash_before_event" => %{"flags" => @procedure, "modes" => ["procedure_crash"]},
    "procedure_slow" => %{"flags" => @procedure, "modes" => ["procedure_slow"]},
    "procedure_missing_event" => %{"flags" => @procedure, "modes" => ["procedure_missing_event"]},
    "procedure_wrong_event" => %{"flags" => @procedure, "modes" => ["procedure_wrong_event"]},
    "procedure_extra_event" => %{"flags" => @procedure, "modes" => ["procedure_extra_event"]},
    "procedure_duplicate_event" => %{
      "flags" => @procedure,
      "modes" => ["procedure_duplicate_event"]
    },
    "procedure_malformed" => %{"flags" => @procedure, "modes" => ["procedure_malformed"]},
    "procedure_read_event" => %{"flags" => @procedure, "modes" => ["procedure_read_event"]},
    "stream_notify" => @stream,
    "stream_indicate" => %{@stream | "flags" => ["read", "indicate"]},
    "stream_capacity" => Map.put(@stream, "characteristics", 65),
    "stream_canary" => %{@stream | "early" => ["PRIVATE_STREAM_VALUE"]},
    "stream_blocked_read" => Map.put(@stream, "modes", ["procedure_blocked"]),
    "stream_blocked_stop" => Map.put(@stream, "modes", ["procedure_blocked", "stop_blocked"]),
    "stream_early_overflow" =>
      Map.merge(@stream, %{"modes" => ["subscribe_error"], "error" => %{"code" => "response_limit"}}),
    "stream_pending_start" => Map.put(@stream, "modes", ["subscribe_blocked"]),
    "stream_wrong_binding" => Map.put(@stream, "modes", ["subscribe_wrong_binding"]),
    "stream_slow_stop" => Map.put(@stream, "modes", ["stop_slow"]),
    "stream_lost_stop_ack" => Map.put(@stream, "modes", ["stop_lost"]),
    "stream_bad_stop_ack" => Map.put(@stream, "modes", ["stop_bad_ack"]),
    "stream_stop_error" =>
      Map.merge(@stream, %{
        "modes" => ["stop_error"],
        "error" => %{"code" => "remote_error", "name" => "org.bluez.Error.Failed"}
      }),
    "stream_wrong_generation" => Map.put(@stream, "modes", ["report_wrong_generation"]),
    "stream_wrong_metadata" => Map.put(@stream, "modes", ["report_wrong_metadata"]),
    "stream_extra_report" => Map.put(@stream, "modes", ["report_extra"]),
    "stream_unknown_report" => Map.put(@stream, "modes", ["report_unknown"]),
    "stream_dispatch_overtake" => Map.put(@stream, "modes", ["read_overtaken"]),
    "stream_runtime" => @runtime,
    "stream_runtime_silent" => %{@runtime | "early" => []},
    "stream_runtime_repeat" => Map.put(@runtime, "modes", ["repeat"]),
    "stream_runtime_pending" => Map.put(@runtime, "modes", ["subscribe_blocked"]),
    "stream_runtime_close_blocked" => Map.put(@runtime, "modes", ["close_blocked"]),
    "stream_runtime_invalid_value" => %{@runtime | "early" => [<<1>>]},
    "stream_runtime_failed" =>
      Map.merge(@runtime, %{
        "modes" => ["subscribe_error"],
        "error" => %{"code" => "not_permitted", "name" => "org.bluez.Error.NotPermitted"}
      })
  }

  @doc false
  @spec options(String.t() | map()) :: {keyword(), String.t()}
  def options(scenario \\ "normal") do
    artifacts = artifacts()

    directory =
      Path.join(
        System.tmp_dir!(),
        "wbl-native-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    executable = Path.join(directory, "host")
    record = executable <> ".jsonl"
    File.cp!(artifacts.executable, executable)
    File.chmod!(executable, 0o700)
    File.write!(executable <> ".json", Jason.encode!(encode(scenario(scenario))))
    on_exit(fn -> cleanup(directory, record) end)

    {:ok, peer} =
      Peer.new(%{adapter: "/org/bluez/hci0", address: "AA:BB:CC:DD:EE:FF", address_type: :random})

    {[
       peer: peer,
       executable: executable,
       executable_sha256: artifacts.executable_sha256,
       guardian: artifacts.guardian,
       guardian_sha256: artifacts.guardian_sha256,
       bus_address: "unix:path=/tmp/test-bus",
       timeout: 5000
     ], record}
  end

  @doc false
  @spec calls(String.t()) :: [map()]
  def calls(path),
    do:
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

  @doc false
  @spec operations(String.t()) :: [String.t()]
  def operations(path), do: for(%{"operation" => operation} <- calls(path), do: operation)

  @doc false
  @spec count(String.t(), String.t()) :: non_neg_integer()
  def count(path, operation), do: Enum.count(operations(path), &(&1 == operation))

  @doc false
  @spec closed(String.t()) :: map() | nil
  def closed(path),
    do: if(File.exists?(path), do: Enum.find(calls(path), &Map.has_key?(&1, "closed")))

  @doc false
  @spec process_gone?(pos_integer()) :: boolean()
  def process_gone?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
      )

    status != 0
  end

  @doc false
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

  defp scenario(name) when is_binary(name), do: Map.fetch!(@scenarios, name)
  defp scenario(scenario) when is_map(scenario), do: scenario

  defp encode(scenario) do
    Map.new(scenario, fn
      {"early", values} -> {"early", Enum.map(values, &bytes/1)}
      {"value", value} -> {"value", bytes(value)}
      entry -> entry
    end)
  end

  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  defp cleanup(directory, record) do
    # Guardian startup precedes the host's first record write; keep the owned
    # directory through that startup cleanup grace.
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

  # One compiled host and guardian serve every scenario in this test run.
  defp artifacts do
    case :persistent_term.get(@artifacts, nil) do
      nil ->
        :global.trans({@artifacts, self()}, fn ->
          :persistent_term.get(@artifacts, nil) || compile()
        end)

      artifacts ->
        artifacts
    end
  end

  defp compile do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wbl-native-host-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    ExUnit.after_suite(fn _ -> File.rm_rf(directory) end)
    executable = Path.join(directory, "host")
    guardian = Path.join(directory, "guardian")

    compile!("c++", [
      "-std=c++17",
      "-O2",
      "-Wall",
      "-Wextra",
      "-Werror",
      "-pedantic",
      "-I",
      Path.join(@root, "priv/bluez/native"),
      Path.join(@root, "test/native/scripted_host.cpp"),
      "-o",
      executable
    ])

    compile!("cc", [
      "-std=c11",
      "-O2",
      "-Wall",
      "-Wextra",
      "-Werror",
      Path.join(@root, "priv/bluez/native/custody.c"),
      "-o",
      guardian
    ])

    artifacts = %{
      executable: executable,
      executable_sha256: digest(executable),
      guardian: guardian,
      guardian_sha256: digest(guardian)
    }

    :persistent_term.put(@artifacts, artifacts)
    artifacts
  end

  defp compile!(name, arguments) do
    compiler = System.find_executable(name) || flunk("native fixture tests require #{name}")

    {output, status} =
      System.cmd(compiler, arguments,
        stderr_to_stdout: true,
        env:
          Enum.map(System.get_env(), fn
            {"PATH", value} -> {"PATH", value}
            {key, _} -> {key, nil}
          end)
      )

    assert status == 0, output
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
