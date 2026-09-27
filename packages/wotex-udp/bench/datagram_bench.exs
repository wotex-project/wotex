alias Wotex.UDP.{Config, Endpoint}

addresses = [
  ipv4: {127, 0, 0, 1},
  ipv6: {0, 0, 0, 0, 0, 0, 0, 1}
]

Benchee.run(
  %{
    "construct local endpoint and finite config" => fn address ->
      {:ok, local} = Endpoint.bind(address, 0)
      {:ok, %Config{}} = Config.new(local: local)
    end
  },
  inputs: addresses,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/datagram.md",
     title: "# Datagram value construction",
     description: "Pure IPv4 and IPv6 endpoint and finite configuration construction."}
  ]
)
