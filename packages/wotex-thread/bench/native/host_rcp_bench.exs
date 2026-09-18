# The public Wotex.Thread API end to end against the pinned OpenThread
# simulation RCP, run by `mix native.bench --package wotex-thread --bench
# host_rcp --workspace DIR` after `mix wotex.thread.native.build` built or
# verified DIR (Linux only). The native build has no RCP, so this script builds
# the software lane's `ot-rcp` (Wotex.Thread.Software.Build) from the
# workspace's pinned OpenThread tree into the benchmark's scratch directory.
# The OpenThread POSIX host creates a Thread network interface, so the process
# needs /dev/net/tun and CAP_NET_ADMIN, as the software lane does.
defmodule Wotex.Thread.Bench.HostRcp do
  @moduledoc false

  alias Wotex.Thread
  alias Wotex.Thread.{Dataset, JoinerAdmission, JoinerIdentity, OpenThread, State}

  # The RCP options of the software lane (Wotex.Thread.Software.Build).
  @rcp_options ~w(-DOT_PLATFORM=simulation -DOT_APP_CLI=OFF -DOT_APP_NCP=OFF -DOT_APP_RCP=ON
    -DOT_FTD=OFF -DOT_MTD=OFF -DOT_RCP=ON -DOT_COMPILE_WARNING_AS_ERROR=ON -DBUILD_TESTING=OFF)
  @timeout 5_000

  @spec main() :: :ok
  def main do
    unless match?({:unix, :linux}, :os.type()), do: Mix.raise("host_rcp requires Linux")
    workspace = System.fetch_env!("WOTEX_THREAD_BENCH_WORKSPACE")
    scratch = System.fetch_env!("WOTEX_THREAD_BENCH_SCRATCH")
    rcp = build_rcp(workspace, scratch)
    storage = Path.join(scratch, "node")
    File.mkdir_p!(storage)
    File.chmod!(storage, 0o700)

    options = [
      client: OpenThread,
      executable: Path.join(workspace, "build/wotex-thread-host"),
      radio_url: "spinel+hdlc+forkpty://#{rcp}?forkpty-arg=7",
      interface: "wthbench",
      storage_path: Path.join(storage, "settings"),
      storage_mode: :create_new,
      allow_network_creation: true,
      owner: self(),
      timeout: 10_000
    ]

    case Thread.connect(options) do
      {:ok, session} ->
        try do
          benchmark(session)
        after
          :ok = Thread.disconnect(session)
        end

      {:error, error} ->
        Mix.raise("Thread.connect failed: #{inspect(error)}#{tun_hint()}")
    end
  end

  defp tun_hint do
    if File.exists?("/dev/net/tun"),
      do: "",
      else:
        "; /dev/net/tun is absent: the OpenThread POSIX host needs it and CAP_NET_ADMIN " <>
          "to create its Thread network interface"
  end

  defp build_rcp(workspace, scratch) do
    {:ok, pins} =
      "../../priv/openthread/dependencies.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Jason.decode()

    source =
      Path.join([
        workspace,
        "sources/openthread",
        "openthread-" <> pins["sources"]["openthread"]["commit"]
      ])

    build = Path.join(scratch, "rcp-build")
    cmake(["-G", "Ninja", "-S", source, "-B", build | @rcp_options])
    cmake(["--build", build, "--target", "ot-rcp", "-j4"])
    Path.join(build, "examples/apps/ncp/ot-rcp")
  end

  defp cmake(arguments) do
    # The build needs no Hex credentials.
    case System.cmd("cmake", arguments, stderr_to_stdout: true, env: [{"HEX_API_KEY", nil}]) do
      {_, 0} -> :ok
      {output, status} -> Mix.raise("cmake #{hd(arguments)} failed (#{status}):\n#{output}")
    end
  end

  defp benchmark(session) do
    active = dataset(1)
    {:ok, %State{role: :leader}} = Thread.form_network(session, active, 30_000)
    {:ok, %{state: :active}} = Thread.commissioner_start(session, timeout: @timeout)
    {:ok, identity} = JoinerIdentity.new(%{eui64: <<0x0200_0000_0000_0042::64>>})

    {:ok, admission} =
      JoinerAdmission.new(%{identity: identity, pskd: "WTEST123", lifetime: 120})

    Benchee.run(
      %{
        "inspect_state" => fn ->
          {:ok, %State{role: :leader}} = Thread.inspect_state(session, [])
        end,
        "get_dataset active" => fn ->
          {:ok, %Dataset{}} = Thread.get_dataset(session, :active, @timeout)
        end,
        "validate_dataset active" => fn ->
          :ok = Thread.validate_dataset(session, active, :active, @timeout)
        end,
        "subscribe State, initial report, unsubscribe" => fn ->
          {:ok, subscription} = Thread.subscribe(session, %{type: :state})
          reference = subscription.reference

          receive do
            {:wotex_thread, ^reference, {:ok, %State{role: :leader}, %{changed_flags: 0}}} -> :ok
          after
            @timeout -> raise "no initial State report"
          end

          :ok = Thread.unsubscribe(session, subscription)
        end,
        "management_active_set newer timestamp" => fn ->
          seconds = Process.get(:active_timestamp, 1) + 1
          Process.put(:active_timestamp, seconds)

          {:ok, %{accepted: true}} =
            Thread.management_active_set(session, %{dataset: dataset(seconds)}, @timeout)
        end,
        "add_joiner and remove_joiner" => fn ->
          {:ok, %{lifetime_s: 120}} = Thread.add_joiner(session, admission, @timeout)
          :ok = Thread.remove_joiner(session, identity, @timeout)
        end
      },
      warmup: 2,
      time: 10,
      memory_time: 0,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.Markdown,
         file: System.fetch_env!("WOTEX_BENCH_OUTPUT"),
         title: "# " <> System.fetch_env!("WOTEX_BENCH_TITLE"),
         description: System.fetch_env!("WOTEX_BENCH_DESCRIPTION")}
      ]
    )

    {:ok, %{state: :disabled}} = Thread.commissioner_stop(session, timeout: @timeout)
    :ok
  end

  # The complete Active Dataset of the benchmark network, with the Active
  # Timestamp `seconds`; the mesh-local prefix is from the ULA range.
  defp dataset(seconds) do
    entries = [
      {0, <<0, 0, 15>>},
      {1, <<0x12, 0x36>>},
      {2, <<1, 2, 3, 4, 5, 6, 7, 10>>},
      {3, "wotex-bench"},
      {4, "0123456789abcdef"},
      {5, "fedcba9876543210"},
      {7, <<0xFD, 1, 2, 3, 4, 5, 6, 9>>},
      {12, <<2, 0xA0, 0xF7, 0xF8>>},
      {14, <<seconds::48, 0::16>>},
      {53, <<0, 4, 0, 0x1F, 0xFF, 0xE0>>}
    ]

    {:ok, dataset} =
      Dataset.decode(
        for {type, value} <- entries, into: <<>>, do: <<type, byte_size(value), value::binary>>
      )

    dataset
  end
end

Wotex.Thread.Bench.HostRcp.main()
