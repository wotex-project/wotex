alias Wotex.Zigbee.{DataRequest, Frame, ZCL, ZDO}

frame = %Frame{type: :areq, subsystem: 4, id: 0x81, payload: :binary.copy(<<0x42>>, 64)}
{:ok, bytes} = Frame.encode(frame)
active_endpoints = <<0x1234::little-16, 0, 0x1234::little-16, 3, 1, 2, 3>>

{:ok, request} =
  DataRequest.new(
    peer_ieee: <<0x00, 0x12, 0x4B, 0x00, 0x23, 0x45, 0x67, 0x89>>,
    route_address: 0x1234,
    destination_endpoint: 2,
    source_endpoint: 1,
    cluster: 6,
    transaction: 7,
    correlation_id: "benchmark",
    data: <<1, 2>>
  )

Benchee.run(
  %{
    "parse 64-byte NCP indication" => fn -> {:ok, [_], <<>>, 0} = Frame.feed(<<>>, bytes) end,
    "decode ZDO active endpoints" => fn ->
      {:ok, _} = ZDO.active_endpoints(active_endpoints)
    end,
    "encode ZCL attribute read" => fn ->
      {:ok, _} = ZCL.read_attributes([0, 1, 2], 7, :client_to_server)
    end,
    "validate AF data request" => fn -> true = DataRequest.valid?(request) end
  },
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/protocol.md",
     title: "# Wotex Zigbee protocol microbenchmarks",
     description:
       "Pure framing, ZDO response decoding, ZCL request encoding and AF request validation on the development host; no serial device or radio."}
  ]
)
