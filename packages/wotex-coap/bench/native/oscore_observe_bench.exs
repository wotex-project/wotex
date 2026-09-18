Code.require_file("support/libcoap_peer.exs", __DIR__)
Code.require_file("support/notification_relay.exs", __DIR__)

alias Wotex.CoAP
alias Wotex.CoAP.Bench.{LibcoapPeer, NotificationRelay}
alias Wotex.CoAP.{Message, Subscription}

# Protected Observe through the public API: one native OSCORE observation (the
# Mix-built helper under custody) of a dynamic resource on the pinned libcoap
# peer. Each iteration changes the resource with a plain UDP PUT and waits for
# the protected notification carrying the new value. Values fit one datagram;
# see oscore_request_bench.exs for why multi-block transfers are left out.
workspace = System.fetch_env!("WOTEX_COAP_BENCH_WORKSPACE")
scratch = System.fetch_env!("WOTEX_COAP_BENCH_SCRATCH")
peer = LibcoapPeer.start!(workspace, scratch, [<<2>>])
path = "/bench/observed"

# A value of `size` bytes that no earlier iteration wrote.
value = fn size ->
  stamp = Integer.to_string(System.unique_integer([:positive, :monotonic]))
  String.pad_leading(stamp, size, "0")
end

try do
  {:ok, writer} = CoAP.connect(LibcoapPeer.plain_options(peer))
  {:ok, %Message{code: 65}} = CoAP.put(writer, path, value.(16), content_format: :text)
  {:ok, session} = CoAP.connect(LibcoapPeer.session_options(peer, <<2>>))
  relay = NotificationRelay.start_link()
  {:ok, %Subscription{} = handle} = CoAP.subscribe(session, %{path: path, receiver: relay})

  notify = fn size ->
    payload = value.(size)
    :ok = NotificationRelay.expect(relay, payload)
    {:ok, %Message{code: 68}} = CoAP.put(writer, path, payload, content_format: :text)
    :ok = NotificationRelay.await(payload, 5_000)
  end

  try do
    Benchee.run(
      %{
        "change and notify, 16-byte value" => fn -> notify.(16) end,
        "change and notify, 512-byte value" => fn -> notify.(512) end
      },
      warmup: 1,
      time: 5,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.Markdown,
         file: System.fetch_env!("WOTEX_BENCH_OUTPUT"),
         title: "# " <> System.fetch_env!("WOTEX_BENCH_TITLE"),
         description: System.fetch_env!("WOTEX_BENCH_DESCRIPTION")}
      ]
    )
  after
    :ok = CoAP.unsubscribe(session, handle)
    CoAP.disconnect(writer)
  end
after
  LibcoapPeer.stop(peer)
end
