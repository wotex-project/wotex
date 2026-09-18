Code.require_file("support/credentials.exs", __DIR__)
Code.require_file("support/peer.exs", __DIR__)

alias Wotex.OPCUA.Bench.NativePeer
alias Wotex.OPCUA.Subscription

# `mix native.bench --package wotex-opcua --workspace DIR` runs this script
# after `wotex.opcua.native.build` built DIR.
workspace = System.fetch_env!("WOTEX_BENCH_WORKSPACE")
report = System.fetch_env!("WOTEX_BENCH_OUTPUT")
peer = NativePeer.start!(workspace, Path.join(System.fetch_env!("WOTEX_BENCH_SCRATCH"), "peer"))
options = NativePeer.session_options(peer, workspace)
burst = "ns=#{peer.namespace};s=burst"
latencies = :ets.new(:notification_latency, [:public, :duplicate_bag])

# OPC UA DateTime ticks (100 ns since 1601-01-01) as Unix nanoseconds.
unix_ns = fn ticks -> (ticks - 116_444_736_000_000_000) * 100 end

# Benchee measures each job in its own process, which owns the Session and
# receives the subscription's deliveries.
subscribe = fn _ ->
  {:ok, session} = Wotex.OPCUA.connect(options)

  {:ok, %Subscription{reference: reference} = subscription} =
    Wotex.OPCUA.subscribe(session, %{
      node_id: burst,
      publishing_interval_ms: 10,
      sampling_interval_ms: 0,
      queue_size: 10,
      keepalive_count: 10,
      lifetime_count: 30
    })

  receive do
    {:wotex_opcua, ^reference, {:ok, _, %{"sequence" => 1}}} -> :ok
  after
    5000 -> raise "no initial notification"
  end

  %{session: session, subscription: subscription}
end

unsubscribe = fn %{session: session, subscription: subscription} ->
  :ok = Wotex.OPCUA.unsubscribe(session, subscription)
  :ok = NativePeer.flush(subscription.reference)
  :ok = Wotex.OPCUA.disconnect(session)
end

# The five values of one burst arrive in order, without overflow; each records
# PublishTime to receipt and source timestamp to receipt.
receive_burst = fn reference, last ->
  for offset <- 4..0//-1 do
    expected = last - offset

    receive do
      {:wotex_opcua, ^reference,
       {:ok, %{"value" => %{"value" => ^expected}, "source_timestamp" => source},
        %{"publish_time" => published, "overflow" => false}}} ->
        received = System.os_time(:nanosecond)

        :ets.insert(
          latencies,
          {:sample, received - unix_ns.(published), received - unix_ns.(source)}
        )
    after
      5000 -> raise "notification #{expected} was not delivered"
    end
  end
end

Benchee.run(
  %{
    "Five data changes to five delivered notifications" => fn %{subscription: subscription} ->
      receive_burst.(subscription.reference, NativePeer.burst(peer))
    end
  },
  before_scenario: subscribe,
  after_scenario: unsubscribe,
  warmup: 1,
  time: 5,
  memory_time: 0,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: report,
     title: "# " <> System.fetch_env!("WOTEX_BENCH_TITLE"),
     description: System.fetch_env!("WOTEX_BENCH_DESCRIPTION")}
  ]
)

:ok = NativePeer.await_idle!(peer)
:ok = NativePeer.stop(peer)

samples = :ets.lookup(latencies, :sample)

duration = fn
  nanoseconds when nanoseconds < 1_000_000 ->
    "#{round(nanoseconds / 1000)} µs"

  nanoseconds ->
    :erlang.float_to_binary(nanoseconds / 1_000_000, decimals: 2) <> " ms"
end

row = fn label, values ->
  sorted = Enum.sort(values)
  count = length(sorted)
  at = fn quantile -> Enum.at(sorted, min(count - 1, floor(quantile * count))) end

  "| #{label} | #{count} | #{duration.(hd(sorted))} | #{duration.(at.(0.5))} | " <>
    "#{duration.(Enum.sum(sorted) / count)} | #{duration.(at.(0.99))} | " <>
    "#{duration.(List.last(sorted))} |"
end

# Benchee's report ends with an HTML table, which only a blank line closes.
File.write!(
  report,
  """


  ## Notification delivery latency

  Every notification the job received, measured with the host's realtime clock,
  which the peer shares: from the PublishTime of the server's NotificationMessage
  to receipt by the subscribing process, which covers the server's encoding and
  message security, the loopback connection, the SDK's decoding, the native
  host's sequence check and value projection, custody, the BEAM host's frame
  validation and delivery; and from the value's source timestamp, taken when the
  peer wrote it, to receipt, which adds the wait for the next publishing cycle.

  | Interval | Notifications | Minimum | Median | Mean | 99th percentile | Maximum |
  | :-- | --: | --: | --: | --: | --: | --: |
  #{row.("PublishTime to receipt", Enum.map(samples, &elem(&1, 1)))}
  #{row.("Source timestamp to receipt", Enum.map(samples, &elem(&1, 2)))}
  """,
  [:append]
)
