defmodule Wotex.Matter.NativeLifecycleStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Native}

  @moduletag :software
  @moduletag :interop
  @moduletag timeout: 300_000

  test "real peer reads, concurrent callers and repeated native ownership return resources" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_STRESS_FIXTURE") |> File.read!() |> Jason.decode!()

    controller = fixture["controller"]

    options =
      [
        client: Native,
        lifecycle: :persistent,
        storage_mode: :open_existing,
        authority: :stored,
        timeout: 10_000
      ] ++
        Enum.map(
          [
            :executable,
            :storage_path,
            :vendor_id,
            :fabric_id,
            :controller_node_id,
            :paa_trust_store
          ],
          &{&1, Map.fetch!(controller, Atom.to_string(&1))}
        )

    node = %{fabric_id: options[:fabric_id], node_id: Map.fetch!(fixture, "node_id")}

    address =
      connected(options, fn session, _child ->
        assert {:ok, catalogue} = Matter.discover_endpoints(session, node)

        [endpoint | _] =
          catalogue.endpoints
          |> Enum.filter(fn entry ->
            match?({:ok, _}, entry.server_clusters) and
              6 in elem(entry.server_clusters, 1).value
          end)
          |> Enum.sort_by(& &1.endpoint)

        Map.merge(node, %{endpoint: endpoint.endpoint, cluster: 6, member: 0})
      end)

    baseline_ports = MapSet.new(Port.list())

    samples =
      connected(options, fn session, child ->
        value = read(session, address)
        baseline_fds = fd_count(child)
        baseline_monitors = monitors(session.handle.pid)

        samples =
          for count <- 1..10 do
            for _ <- 1..100, do: assert(read(session, address) == value)
            assert fd_count(child) == baseline_fds
            assert monitors(session.handle.pid) == baseline_monitors
            %{completed_reads: count * 100, rss_kib: rss(child), fds: fd_count(child)}
          end

        results =
          1..32
          |> Task.async_stream(fn _ -> read(session, address) end,
            max_concurrency: 32,
            ordered: false,
            timeout: 15_000
          )
          |> Enum.to_list()

        assert length(results) == 32
        assert Enum.all?(results, &(&1 == {:ok, value}))
        assert fd_count(child) == baseline_fds

        for _ <- 1..100 do
          parent = self()

          receiver =
            spawn(fn ->
              receive do
                {:wotex_matter, _, {:ok, _, _}} -> send(parent, {:initial, self()})
              end

              Process.sleep(:infinity)
            end)

          monitor = Process.monitor(receiver)

          try do
            assert {:ok, _} =
                     Matter.subscribe(session, %{
                       kind: :attribute,
                       paths: [address],
                       receiver: receiver,
                       min_interval_s: 0,
                       max_interval_s: 1,
                       resubscribe: false
                     })

            assert_receive {:initial, ^receiver}, 3_000
            Process.exit(receiver, :kill)
            assert_receive {:DOWN, ^monitor, :process, ^receiver, :killed}, 1_000
            assert drained?(session.handle.pid, 100)
            assert monitors(session.handle.pid) == baseline_monitors
            assert read(session, address) == value
            assert fd_count(child) == baseline_fds
            # Allow the software server to observe cancellation of its old client.
            Process.sleep(1050)
          after
            Process.exit(receiver, :kill)
            Process.demonitor(monitor, [:flush])
          end
        end

        samples
      end)

    assert MapSet.new(Port.list()) == baseline_ports

    for _ <- 1..100 do
      connected(options, fn session, _ -> read(session, address) end)
      assert MapSet.new(Port.list()) == baseline_ports
    end

    File.write!(
      fixture["result_path"],
      Jason.encode!(%{
        status: "passed",
        sequential_reads: 1000,
        concurrent_callers: 32,
        receiver_death_cycles: 100,
        open_close_cycles: 100,
        rss_samples: samples,
        endpoint: address.endpoint,
        owned_ports_after_cleanup: 0
      }),
      [:exclusive]
    )
  end

  defp connected(options, function) do
    assert {:ok, session} = Matter.connect(options)
    owner = session.handle.pid
    monitor = Process.monitor(owner)
    {:links, links} = Process.info(owner, :links)
    [port] = Enum.filter(links, &is_port/1)
    {:os_pid, child} = Port.info(port, :os_pid)

    try do
      function.(session, child)
    after
      assert :ok = Matter.disconnect(session)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1000
      assert child_stopped?(child, 100)
    end
  end

  defp read(session, address) do
    assert {:ok, %AttributeReport{value: %{type: :boolean} = value}} =
             Matter.read_attribute(session, address)

    value
  end

  defp drained?(_, 0), do: false

  defp drained?(owner, remaining) do
    state = :sys.get_state(owner, 1000)

    if Enum.all?(
         [
           :subscriptions,
           :subscription_ids,
           :subscription_monitors,
           :internal_requests
         ],
         &(Map.fetch!(state, &1) == %{})
       ) and state.report_ledger.pending == %{} and state.report_ledger.streams == %{} do
      true
    else
      Process.sleep(10)
      drained?(owner, remaining - 1)
    end
  end

  defp child_stopped?(_, 0), do: false

  defp child_stopped?(pid, remaining) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        child_stopped?(pid, remaining - 1)

      {_, _} ->
        true
    end
  end

  defp monitors(owner) do
    {:monitors, values} = Process.info(owner, :monitors)
    MapSet.new(values)
  end

  defp fd_count(pid), do: "/proc/#{pid}/fd" |> File.ls!() |> length()

  defp rss(pid) do
    [_, value] = Regex.run(~r/^VmRSS:\s+(\d+)\s+kB$/m, File.read!("/proc/#{pid}/status"))
    String.to_integer(value)
  end
end
