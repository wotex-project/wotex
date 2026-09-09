defmodule Wotex.BACnet.CStackShutdownTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.Test.CStackPeer
  @moduletag peer_shutdown: true, capture_log: true
  @moduletag requirements: ["WBA-C09", "WBA-S03", "WBA-S04", "WBA-V14"]

  test "WBA-CP25 WBA-C09 peer exit releases live COV transactions and local custody" do
    before = CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
    session = CStackPeer.connect(timeout: 300)
    writer = CStackPeer.connect(timeout: 300)
    resources = CStackPeer.resources(session)
    writer_resources = CStackPeer.resources(writer)

    on_exit(fn ->
      BACnet.disconnect(session)
      BACnet.disconnect(writer)
    end)

    assert {:ok, %Encoding{type: :real, value: initial}} = BACnet.read_property(session, 1, 1, 85)

    subscriptions =
      for type <- [:cov, :cov_property] do
        request = %{
          type: type,
          object_type: 1,
          instance: 1,
          device_instance: 123,
          lifetime: 4,
          renew: false,
          confirmed: true
        }

        request = if type == :cov_property, do: Map.put(request, :property, 85), else: request
        assert {:ok, subscription} = BACnet.subscribe(session, request)
        reference = subscription.reference
        assert_receive {:wotex_bacnet, ^reference, {:ok, _, _}}, 1000
        subscription
      end

    CStackPeer.await(&(&1["active_subscribers"] == 2 and &1["active_invoke_ids"] == 0))
    client = session.handle.stack.client
    :ok = :sys.suspend(client)

    pending =
      try do
        assert {:ok, :written} =
                 BACnet.send(writer, %{
                   type: :write_property,
                   object_type: 1,
                   instance: 1,
                   property: 85,
                   priority: 16,
                   value: Encoding.create!({:real, initial + 5.0})
                 })

        CStackPeer.await(&(&1["active_subscribers"] == 2 and &1["active_invoke_ids"] == 2), 75)
        stopped = CStackPeer.control("quit")
        assert stopped["object_subscribers"] == 1 and stopped["property_subscribers"] == 1
        assert stopped["active_invoke_ids"] == 2
        stopped
      after
        if Process.alive?(client), do: :sys.resume(client)
      end

    assert {:error, %{code: :deadline_exceeded, effect: :none}} =
             BACnet.read_property(session, 1, 1, 85)

    monitors = Enum.map(subscriptions, &Process.monitor(&1.pid))
    started = System.monotonic_time(:millisecond)
    CStackPeer.close(session, resources)

    for monitor <- monitors do
      remaining = max(started + 1100 - System.monotonic_time(:millisecond), 0)
      assert_receive {:DOWN, ^monitor, :process, _, _}, remaining
    end

    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed <= 1100
    CStackPeer.close(writer, writer_resources)

    result = %{
      case: "WBA-CP25",
      server_before: before,
      server_before_exit: pending,
      read_after_peer_exit: "deadline_exceeded",
      read_effect: "none",
      local_cleanup_ms: elapsed,
      owned_processes_after: 0,
      owned_sockets_after: 0
    }

    path = Path.join(System.fetch_env!("WOTEX_BACNET_RESULTS_DIR"), "WBA-CP25.json")
    File.write!(path, Jason.encode!(result, pretty: true))
  end
end
