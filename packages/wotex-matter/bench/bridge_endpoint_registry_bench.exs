alias Wotex.Matter.Bridge.EndpointRegistry

{:ok, empty} = EndpointRegistry.new(max_endpoint: 1_024)
{:ok, 3, one} = EndpointRegistry.allocate(empty, "benchmark-device")

many =
  Enum.reduce(1..256, empty, fn number, registry ->
    {:ok, _, updated} = EndpointRegistry.allocate(registry, "device-#{number}")
    updated
  end)

snapshot = EndpointRegistry.snapshot(many)

Benchee.run(
  %{
    "allocate one stable endpoint" => fn ->
      {:ok, 3, _} = EndpointRegistry.allocate(empty, "benchmark-device")
    end,
    "repeat existing identity" => fn ->
      {:ok, 3, _} = EndpointRegistry.allocate(one, "benchmark-device")
    end,
    "validate 256-endpoint restart snapshot" => fn ->
      {:ok, _} = EndpointRegistry.restore(snapshot)
    end
  },
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/bridge_endpoint_registry.md",
     title: "# Matter bridge endpoint custody microbenchmarks",
     description:
       "Pure endpoint identity operations and 256-device restart validation; no native server or controller peer."}
  ]
)
