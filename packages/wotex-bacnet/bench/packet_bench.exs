Code.require_file("support/values.exs", __DIR__)

alias Wotex.BACnet.Bench.Values
alias Wotex.BACnet.IPv4Packet

inputs =
  Map.new(Values.cases(), fn {label, _, value, property} ->
    tag = Values.tag(value)
    {:ok, ack} = IPv4Packet.encode(Values.read_ack(property, tag), false)

    {label,
     %{
       read: Values.read_request(property),
       write: Values.write_request(property, tag),
       ack: ack
     }}
  end)

Benchee.run(
  %{
    "encode ReadProperty request" => fn %{read: read} ->
      {:ok, _} = IPv4Packet.encode(read, false)
    end,
    "encode WriteProperty request" => fn %{write: write} ->
      {:ok, _} = IPv4Packet.encode(write, false)
    end,
    "decode ReadProperty-ACK datagram" => fn %{ack: ack} ->
      {:ok, {:apdu, _, _, _}} = IPv4Packet.decode(ack)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/packet.md",
     title: "# BACnet/IP datagram encoding and decoding",
     description: """
     `Wotex.BACnet.IPv4Packet.encode/3` of confirmed ReadProperty and
     WriteProperty (priority 8) service requests given as BACstack APDU values,
     as the package's client builds them, and `Wotex.BACnet.IPv4Packet.decode/1`
     of the unicast ReadProperty-ACK datagram. The Property values are a Real
     present-value and CharacterString values of 64 bytes and 1 KiB. Encoding
     includes BACstack APDU and NPCI encoding, the 1476-byte APDU limit and the
     BVLL envelope; decoding checks the BVLL size and decodes the BVLC and NPCI
     with the pinned SDK codecs while retaining the APDU bytes.
     """}
  ]
)
