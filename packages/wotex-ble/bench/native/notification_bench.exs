# Notification and indication round trips through the public API on a
# persistent BlueZ session, run by `mix native.bench --package wotex-ble
# --workspace /abs/dir` on a Linux host with the software lane's private bus,
# bluetoothd, virtual controllers and GATT peer (WOTEX_BLE_SOFTWARE_CONFIG).
# One round trip is the peer's control request that emits the next uint8
# value and the subscriber's receipt of that exact value. Benchee measures in
# a process of its own, so each scenario subscribes there (the subscriber is
# the caller) and unsubscribes afterwards.
Code.require_file("support/software.exs", __DIR__)

alias Wotex.BLE
alias Wotex.BLE.Bench.Software

socket = Software.control_socket!()
config = Software.command(socket, "reset")
{:ok, session} = BLE.connect(Software.options(config))

try do
  {:ok, page} = BLE.discover(session)
  counter = :counters.new(1, [])

  subscribe = fn mode ->
    request = %{address: Software.target(page, mode), mode: mode, value_type: :uint8}
    {:ok, subscription} = BLE.subscribe(session, request)
    {mode, subscription}
  end

  round_trip = fn {mode, subscription} ->
    :ok = :counters.add(counter, 1, 1)
    value = rem(:counters.get(counter, 1), 256)
    reference = subscription.reference
    hex = Base.encode16(<<value>>, case: :lower)
    Software.command(socket, "value", %{label: Atom.to_string(mode), hex: hex, emit: true})

    receive do
      {:wotex_ble, ^reference, {:ok, ^value, %{source: :bluez_value_change}}} -> :ok
    after
      5000 -> raise "no #{mode} report of #{value} within 5 s"
    end
  end

  Benchee.run(
    %{"emit and receive" => round_trip},
    inputs: [{"notify", :notify}, {"indicate", :indicate}],
    before_scenario: subscribe,
    after_scenario: fn {_, subscription} -> :ok = BLE.unsubscribe(session, subscription) end,
    warmup: 1,
    time: 5,
    formatters: Software.formatters()
  )
after
  :ok = BLE.disconnect(session)
end
