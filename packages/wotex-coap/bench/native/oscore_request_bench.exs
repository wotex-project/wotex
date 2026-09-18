Code.require_file("support/libcoap_peer.exs", __DIR__)

alias Wotex.CoAP
alias Wotex.CoAP.Bench.LibcoapPeer
alias Wotex.CoAP.Message

# Protected unary requests through the public API: one native OSCORE session
# (the Mix-built helper under custody) against the pinned libcoap peer. The
# resources are dynamic ones a plain UDP writer creates before the run. Every
# request and response fits one datagram. Multi-block transfers are left out:
# in a Block2 transfer the peer intermittently acknowledges a block request
# whose Message ID equals that of its own separate response, which the helper
# acknowledges right after the request, and then never sends the response.
workspace = System.fetch_env!("WOTEX_COAP_BENCH_WORKSPACE")
scratch = System.fetch_env!("WOTEX_COAP_BENCH_SCRATCH")
peer = LibcoapPeer.start!(workspace, scratch, [<<1>>])

pattern = fn size ->
  binary_part(
    :binary.copy(:erlang.list_to_binary(Enum.to_list(0..255)), div(size, 256) + 1),
    0,
    size
  )
end

small = pattern.(64)
medium = pattern.(512)
body = :binary.copy(<<0x5A>>, 512)

try do
  {:ok, writer} = CoAP.connect(LibcoapPeer.plain_options(peer))
  {:ok, %Message{code: 65}} = CoAP.put(writer, "/bench/small", small, content_format: :octet_stream)

  {:ok, %Message{code: 65}} =
    CoAP.put(writer, "/bench/medium", medium, content_format: :octet_stream)

  {:ok, %Message{code: 65}} =
    CoAP.put(writer, "/bench/written", body, content_format: :octet_stream)

  :ok = CoAP.disconnect(writer)

  {:ok, session} = CoAP.connect(LibcoapPeer.session_options(peer, <<1>>))

  try do
    Benchee.run(
      %{
        "GET, 64-byte representation" => fn ->
          {:ok, %Message{code: 69, payload: ^small}} = CoAP.get(session, "/bench/small")
        end,
        "GET, 512-byte representation" => fn ->
          {:ok, %Message{code: 69, payload: ^medium}} = CoAP.get(session, "/bench/medium")
        end,
        "PUT, 512-byte body" => fn ->
          {:ok, %Message{code: 68}} =
            CoAP.put(session, "/bench/written", body, content_format: :octet_stream)
        end
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
    :ok = CoAP.disconnect(session)
  end
after
  LibcoapPeer.stop(peer)
end
