defmodule Wotex.BACnet.DiscoveryFixtureTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.{APDU, NPCI, ObjectIdentifier}
  alias BACnet.Protocol.Services.WhoIs
  alias Wotex.BACnet.{DiscoveryOwner, DiscoveryWindow, Error}
  alias Wotex.BACnet.Test.{DiscoveryClock, DiscoveryPeer}

  @moduletag :capture_log
  @corpus Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)
  @external_resource @corpus
  @cases Jason.decode!(File.read!(@corpus))["cases"]
  @moduletag corpus_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(@corpus)), case: :lower)

  test "WBA-N04 WBA-N05 WBA-F10 WBA-F11 actual owner consumes scripts with virtual timers and exact ownership counts" do
    for vector <- @cases, vector["id"] in ["WBA-F10", "WBA-F11"] do
      input = vector["input"]
      config = input["discovery"]

      options = %{
        destination: source(config["destination"]),
        timeout_ms: config["timeout_ms"],
        max_devices: config["max_devices"]
      }

      assert {:ok, window} =
               DiscoveryWindow.new(
                 options,
                 input["low_limit"],
                 input["high_limit"],
                 0,
                 input["session_timeout_ms"]
               )

      {owner, peer, clock, token, monitor} = start(window)
      assert_receive {:discovery_peer_send, ^peer, sent}
      assert sent.worker_alive
      assert sent.caller_alive
      assert sent.deadline == 91
      worker_monitor = Process.monitor(sent.worker)
      assert_receive {:DOWN, ^worker_monitor, :process, _, _}
      assert :sys.get_state(owner).phase == :collecting

      Enum.each(input["events"], fn event ->
        DiscoveryClock.advance(clock, event["at_ms"])
        deliver(owner, peer, event)
      end)

      assert_receive {:discovery_result, ^owner, ^token, outcome}
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      snapshot = DiscoveryPeer.snapshot(peer)

      counters = %{
        "active_owned_listeners" => map_size(snapshot.listeners),
        "active_owned_timers" => DiscoveryClock.timers(clock)
      }

      projection =
        case outcome do
          {:ok, devices} ->
            {:ok, service} = WhoIs.from_apdu(sent.apdu)

            Map.merge(counters, %{
              "ok" => Enum.map(devices, &device_projection/1),
              "borrowed_client_alive" => Process.alive?(peer),
              "listener_registration_before_send" =>
                sent.registered and snapshot.actions == [:register, :send, :unregister],
              "sent_services" => [
                %{
                  "service" => "who_is",
                  "destination" => address_projection(sent.destination),
                  "low_limit" => service.device_id_low_limit,
                  "high_limit" => service.device_id_high_limit
                }
              ]
            })

          {:error, error} ->
            Map.merge(counters, %{
              "error" => %{
                "code" => Atom.to_string(error.code),
                "effect" => Atom.to_string(error.effect)
              },
              "result_count" => 0
            })
        end

      assert projection == vector["expectation"]["value"], vector["id"]
    end
  end

  test "WBA-N04 failed registration, failed send and rejected cleanup never become an empty success" do
    options = %{destination: {{192, 0, 2, 255}, 47_808}, timeout_ms: 100, max_devices: 1}

    for {port_options, code} <-
          [[register_error: true], [send_error: true], [unregister_error: true]]
          |> Enum.zip([:connection_closed, :transport_error, :cleanup_failed]) do
      {:ok, window} = DiscoveryWindow.new(options, nil, nil, 0, 1000)
      {owner, peer, clock, token, monitor} = start(window, port_options)

      unless port_options[:register_error] do
        assert_receive {:discovery_peer_send, ^peer, _}
      end

      if port_options[:unregister_error], do: DiscoveryClock.advance(clock, 100)
      assert_receive {:discovery_result, ^owner, ^token, {:error, %Error{code: ^code}}}
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      assert DiscoveryClock.timers(clock) == 0
      assert Process.alive?(peer)
    end
  end

  test "WBA-N04 window expiry before registration or send acknowledgment cannot manufacture success" do
    options = %{destination: {{192, 0, 2, 255}, 47_808}, timeout_ms: 100, max_devices: 1}

    for pending <- [:register_pending, :send_pending] do
      {:ok, window} = DiscoveryWindow.new(options, nil, nil, 0, 1000)
      {owner, peer, clock, token, monitor} = start(window, [{pending, true}])
      if pending == :send_pending, do: assert_receive({:discovery_peer_send, ^peer, _})
      DiscoveryClock.advance(clock, 100)
      assert_receive {:discovery_result, ^owner, ^token, {:error, %Error{code: :deadline_exceeded}}}
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      assert DiscoveryClock.timers(clock) == 0
      assert map_size(DiscoveryPeer.snapshot(peer).listeners) == 0
      for sent <- DiscoveryPeer.snapshot(peer).sent, do: refute(Process.alive?(sent.worker))
    end
  end

  test "WBA-N04 version-one COV wrapper remains connectable but never receives a discovery command" do
    alias Wotex.BACnet
    alias Wotex.BACnet.BACstack

    peer =
      start_supervised!({DiscoveryPeer, [owner: self(), capabilities: {:wotex_client, 1, :cov}]})

    assert :ok = Wotex.BACnet.StackClient.verify(peer, 100)

    {:ok, session} =
      BACnet.connect(
        client: BACstack,
        stack_client: peer,
        stack_client_kind: :wotex,
        destination: {{192, 0, 2, 20}, 47_808},
        timeout: 1000,
        discovery: %{destination: {{192, 0, 2, 255}, 47_808}, timeout_ms: 100, max_devices: 1}
      )

    assert {:error, %Error{code: :not_supported}} = BACnet.who_is(session)
    assert :ok = BACnet.disconnect(session)
    snapshot = DiscoveryPeer.snapshot(peer)
    assert snapshot.actions == []
    assert snapshot.listeners == %{}
    assert Process.alive?(peer)
  end

  test "WBA-C03 WBA-N04 held cleanup uses one finite clock and explicit close can only shorten it" do
    for shorten <- [false, true] do
      {owner, peer, clock, token, monitor} = start(default_window(), unregister_pending: true)
      sent = sent(peer, owner)
      DiscoveryClock.advance(clock, 100)
      assert :sys.get_state(owner).phase == :closing

      if shorten do
        send(owner, {:session_closing, self(), 120})
        assert :sys.get_state(owner).cleanup_deadline == 120
      end

      expires = if shorten, do: 120, else: 1100
      DiscoveryClock.advance(clock, expires - 1)
      assert Process.alive?(owner)
      DiscoveryClock.advance(clock, expires)
      code = if shorten, do: :connection_closed, else: :cleanup_failed
      assert_receive {:discovery_result, ^owner, ^token, {:error, %Error{code: ^code}}}
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      refute Process.alive?(sent.worker)
      assert DiscoveryClock.timers(clock) == 0
      assert Process.alive?(peer)
    end
  end

  test "WBA-N04 loss of a send worker or client is terminal and releases owned timers" do
    for lost <- [:worker, :client] do
      {owner, peer, clock, token, monitor} = start(default_window(), send_pending: true)
      assert_receive {:discovery_peer_send, ^peer, sent}
      Process.exit(if(lost == :worker, do: sent.worker, else: peer), :kill)
      assert_receive {:discovery_result, ^owner, ^token, {:error, %Error{code: :connection_closed}}}
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      refute Process.alive?(sent.worker)
      assert DiscoveryClock.timers(clock) == 0
    end
  end

  test "WBA-N04 malformed send acknowledgment and a flooded listener both fail closed" do
    {owner, peer, clock, token, monitor} = start(default_window(), send_result: :unexpected)
    assert_receive {:discovery_peer_send, ^peer, _}
    assert_receive {:discovery_result, ^owner, ^token, {:error, %Error{code: :transport_error}}}
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    assert DiscoveryClock.timers(clock) == 0

    {owner, peer, clock, token, monitor} = start(default_window())
    sent(peer, owner)
    :ok = :sys.suspend(owner)

    for _ <- 1..1001 do
      send(
        owner,
        {:bacnet_client, nil, :malformed, {{{192, 0, 2, 20}, 47_808}, nil, NPCI.new([])}, peer}
      )
    end

    :ok = :sys.resume(owner)
    assert_receive {:discovery_result, ^owner, ^token, {:error, %Error{code: :slow_consumer}}}
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    assert DiscoveryClock.timers(clock) == 0
    assert map_size(DiscoveryPeer.snapshot(peer).listeners) == 0
  end

  defp default_window do
    {:ok, window} =
      DiscoveryWindow.new(
        %{destination: {{192, 0, 2, 255}, 47_808}, timeout_ms: 100, max_devices: 1},
        nil,
        nil,
        0,
        1000
      )

    window
  end

  defp sent(peer, owner) do
    assert_receive {:discovery_peer_send, ^peer, sent}
    monitor = Process.monitor(sent.worker)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    assert :sys.get_state(owner).phase == :collecting
    sent
  end

  defp start(window, options \\ []) do
    clock = start_supervised!({DiscoveryClock, []}, id: make_ref())

    child =
      Supervisor.child_spec({DiscoveryPeer, Keyword.put(options, :owner, self())},
        id: make_ref(),
        restart: :temporary
      )

    peer = start_supervised!(child)
    token = make_ref()

    # The owner can finish before `start_link/1` returns to this process, so
    # the monitor is created atomically with the process.
    {:ok, {owner, monitor}} =
      :gen_server.start_monitor(
        DiscoveryOwner,
        %{
          client: peer,
          session: self(),
          from: {self(), make_ref()},
          token: token,
          window: window,
          clock: fn -> DiscoveryClock.now(clock) end,
          schedule: fn pid, message, delay ->
            DiscoveryClock.schedule(clock, pid, message, delay)
          end,
          cancel_timer: fn ref -> DiscoveryClock.cancel(clock, ref) end
        },
        []
      )

    {owner, peer, clock, token, monitor}
  end

  defp deliver(owner, peer, %{"event" => "i_am", "device" => device}) do
    assert device["segmentation"] == "no_segmentation"

    apdu = %APDU.UnconfirmedServiceRequest{
      service: :i_am,
      parameters: [
        {:object_identifier, %ObjectIdentifier{type: :device, instance: device["instance"]}},
        {:unsigned_integer, device["max_apdu"]},
        {:enumerated, 3},
        {:unsigned_integer, device["vendor_id"]}
      ]
    }

    send(
      owner,
      {:bacnet_client, nil, apdu, {source(device["source"]), nil, NPCI.new([])}, peer}
    )

    barrier(owner)
  end

  defp deliver(owner, _, _), do: barrier(owner)

  defp barrier(owner) do
    :sys.get_state(owner)
  catch
    :exit, _ -> :ok
  end

  defp source([octets, port]), do: {List.to_tuple(octets), port}
  defp address_projection({ip, port}), do: [Tuple.to_list(ip), port]

  defp device_projection(device),
    do: %{
      "source" => address_projection(device.source),
      "instance" => device.instance,
      "max_apdu" => device.max_apdu,
      "segmentation" => Atom.to_string(device.segmentation),
      "vendor_id" => device.vendor_id
    }
end
