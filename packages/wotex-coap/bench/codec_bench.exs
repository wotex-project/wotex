Code.require_file("support/messages.exs", __DIR__)

alias Wotex.CoAP.Bench.Messages
alias Wotex.CoAP.Codec

messages = %{
  "GET request, 4 options" =>
    Messages.request(1, [
      {11, "properties"},
      {11, "temperature"},
      {15, "unit=Cel"},
      {17, Codec.uint(50)}
    ]),
  "2.05 notification, 6 options, 256-byte payload" =>
    Messages.reply(
      69,
      [
        {4, Messages.etag()},
        {6, Codec.uint(70_000)},
        {12, Codec.uint(50)},
        {14, Codec.uint(60)},
        {23, Messages.block(0, true, 256)},
        {28, Codec.uint(4096)}
      ],
      binary_part(Messages.json(40), 0, 256)
    ),
  "PUT Block1, 14 options, 1024-byte payload" =>
    Messages.request(
      3,
      [
        {3, "thing.example"},
        {7, Codec.uint(5683)},
        {11, "things"},
        {11, "building-1"},
        {11, "floor-2"},
        {11, "properties"},
        {11, "configuration"},
        {12, Codec.uint(50)},
        {15, "revision=7"},
        {15, "mode=replace"},
        {17, Codec.uint(50)},
        {27, Messages.block(2, true, 1024)},
        {60, Codec.uint(8192)},
        {292, <<0x31, 0x4C, 0x9E, 0x02>>}
      ],
      Messages.body(1024)
    )
}

inputs =
  Map.new(messages, fn {label, message} ->
    {:ok, datagram} = Codec.encode(message)
    {label, %{message: message, datagram: datagram}}
  end)

Benchee.run(
  %{
    "encode" => fn %{message: message} -> {:ok, _} = Codec.encode(message) end,
    "decode" => fn %{datagram: datagram} -> {:ok, _} = Codec.decode(datagram) end,
    "validate options" => fn %{message: message} -> :ok = Codec.validate_options(message) end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/codec.md",
     title: "# CoAP message encoding and decoding",
     description: """
     `Wotex.CoAP.Codec.encode/1`, `Wotex.CoAP.Codec.decode/1` and
     `Wotex.CoAP.Codec.validate_options/1` over three RFC 7252 messages with an
     eight-byte token: a GET with Uri-Path, Uri-Query and Accept; a 2.05
     notification with ETag, Observe, Content-Format, Max-Age, Block2 and Size2
     and a 256-byte payload; and a Block1 PUT with 14 options, including
     extended option deltas for Size1 and Request-Tag, and a 1024-byte payload
     close to the 1152-byte datagram limit. Encoding and decoding include header,
     option ordering and length checks; option validation adds the critical,
     repeat and per-option length rules.
     """}
  ]
)
