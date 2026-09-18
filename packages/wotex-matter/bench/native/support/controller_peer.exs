# Runs inside the linux/amd64 container that bench/native/controller_peer_bench.exs
# starts, with the verified software workspace at /artifacts and a writable
# /run. It starts the pinned all-clusters example peer, commissions it with a
# persistent controller through the public API and measures that API end to
# end: the BEAM client, the Port, the first-party controller host, the
# connectedhomeip controller and the peer over the container network.
Code.require_file("../../../test/support/software/peer.exs", __DIR__)

defmodule Wotex.Matter.Bench.ControllerPeerRun do
  @moduledoc false

  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Native, SoftwarePeer}

  @fabric 1
  @node 0x1234
  @discriminator 3840
  @setup_pin 20_202_021
  @empty %{tag: :anonymous, type: :structure, value: []}

  @spec main() :: :ok
  def main do
    paa = private("/run/paa")

    for name <- ~w(Chip-Test-PAA-FFF1-Cert.der Chip-Test-PAA-NoVID-Cert.der) do
      File.cp!("/artifacts/paa/" <> name, Path.join(paa, name))
      File.chmod!(Path.join(paa, name), 0o600)
    end

    peer = private("/run/peer")
    controller = private("/run/controller")

    {:ok, running} =
      SoftwarePeer.start(
        "/artifacts/bin/chip-all-clusters-app",
        [
          "--KVS",
          Path.join(peer, "peer.kvs"),
          "--secured-device-port",
          "5540",
          "--discriminator",
          Integer.to_string(@discriminator),
          "--passcode",
          Integer.to_string(@setup_pin)
        ],
        cd: peer,
        startup_timeout: 30_000,
        timeout: 3_600_000,
        ready: "Server Listening...",
        log: Path.join(peer, "peer.log")
      )

    try do
      {:ok, session} =
        Matter.connect(
          client: Native,
          lifecycle: :persistent,
          storage_mode: :create_new,
          authority: :generate_root,
          timeout: 60_000,
          executable: "/artifacts/bin/wotex-matter-host",
          storage_path: Path.join(controller, "store"),
          vendor_id: 0xFFF1,
          fabric_id: @fabric,
          controller_node_id: 112_233,
          paa_trust_store: paa
        )

      try do
        benchmark(session)
      after
        :ok = Matter.disconnect(session)
      end
    after
      :ok = SoftwarePeer.stop(running)
    end
  end

  defp benchmark(session) do
    node = %{fabric_id: @fabric, node_id: @node}

    {:ok, %{case: :established}} =
      Matter.commission_on_network(session, %{
        node_id: @node,
        setup_pin: @setup_pin,
        discriminator: @discriminator,
        timeout: 60_000
      })

    {:ok, catalogue} = Matter.discover_endpoints(session, node)
    on_off = Map.merge(node, %{endpoint: serving(catalogue, 0x0006), cluster: 0x0006, member: 0})

    heating =
      Map.merge(node, %{endpoint: serving(catalogue, 0x0201), cluster: 0x0201, member: 0x12})

    toggle = %{on_off | member: 2}

    descriptor =
      for endpoint <- [0, on_off.endpoint],
          member <- 0..3,
          do: Map.merge(node, %{endpoint: endpoint, cluster: 0x001D, member: member})

    title = System.fetch_env!("WOTEX_BENCH_TITLE")

    Benchee.run(
      %{
        "read_attribute OnOff" => fn ->
          {:ok, %AttributeReport{value: %{type: :boolean}}} =
            Matter.read_attribute(session, on_off)
        end,
        "read_paths Descriptor of two endpoints (8 paths)" => fn ->
          {:ok, results} = Matter.read_paths(session, descriptor)
          8 = length(results)
        end,
        "discover_endpoints" => fn ->
          {:ok, %{endpoints: [_ | _]}} = Matter.discover_endpoints(session, node)
        end,
        "write_attribute OccupiedHeatingSetpoint" => fn ->
          {:ok, %{status: 0}} =
            Matter.write_attribute(session, heating, %{tag: :anonymous, type: :i16, value: 2000})
        end,
        "invoke_command OnOff Toggle" => fn ->
          {:ok, %{status: 0}} = Matter.invoke_command(session, toggle, @empty)
        end,
        "Toggle until its OnOff subscription report" =>
          {fn subscription -> toggle_reported(session, toggle, subscription) end,
           before_scenario: fn _ -> subscribe(session, on_off) end,
           after_scenario: fn subscription -> :ok = Matter.unsubscribe(session, subscription) end}
      },
      warmup: 2,
      time: 10,
      memory_time: 0,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.Markdown,
         file: System.fetch_env!("WOTEX_BENCH_OUTPUT"),
         title: "# " <> title,
         description: System.fetch_env!("WOTEX_BENCH_DESCRIPTION")}
      ]
    )

    :ok
  end

  # The first endpoint whose server list names `cluster`.
  defp serving(catalogue, cluster) do
    %{endpoint: endpoint} =
      Enum.find(catalogue.endpoints, fn entry ->
        match?({:ok, %{value: clusters}} when is_list(clusters), entry.server_clusters) and
          cluster in elem(entry.server_clusters, 1).value
      end)

    endpoint
  end

  # Subscribes to OnOff and waits for the priming report, whose value the
  # first toggle inverts.
  defp subscribe(session, on_off) do
    {:ok, subscription} =
      Matter.subscribe(session, %{
        kind: :attribute,
        paths: [on_off],
        min_interval_s: 0,
        max_interval_s: 10,
        resubscribe: false
      })

    reference = subscription.reference

    receive do
      {:wotex_matter, ^reference, {:ok, %{type: :boolean, value: value}, _}} ->
        Process.put(:on_off, value)
    after
      15_000 -> raise "no priming OnOff report"
    end

    subscription
  end

  defp toggle_reported(session, toggle, subscription) do
    expected = not Process.get(:on_off)
    {:ok, %{status: 0}} = Matter.invoke_command(session, toggle, @empty)
    await_report(subscription.reference, expected)
    Process.put(:on_off, expected)
  end

  defp await_report(reference, expected) do
    receive do
      {:wotex_matter, ^reference, {:ok, %{value: ^expected}, _}} -> :ok
      {:wotex_matter, ^reference, {:ok, _, _}} -> await_report(reference, expected)
    after
      15_000 -> raise "no OnOff report of #{expected}"
    end
  end

  defp private(path) do
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    path
  end
end

Wotex.Matter.Bench.ControllerPeerRun.main()
