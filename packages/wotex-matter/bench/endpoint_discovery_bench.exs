Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/topology.exs", __DIR__)

alias Wotex.Matter.Bench.{Client, Topology}
alias Wotex.Matter.{EndpointCatalogue, Native, PathResults}

inputs =
  Map.new(Topology.sizes(), fn {label, count} ->
    input = Topology.input(count)
    {:ok, session} = Wotex.Matter.connect(client: Client, descriptors: input.descriptors)
    {label, Map.put(input, :session, session)}
  end)

Benchee.run(
  %{
    "admit native response frames" => fn %{batches: batches} ->
      Enum.each(batches, fn %{frame: frame} -> {:ok, _} = Native.Wire.frame(frame) end)
    end,
    "normalize batch-read results" => fn %{batches: batches} ->
      Enum.each(batches, fn batch ->
        {:ok, _} = PathResults.normalize(batch.requested, batch.results)
      end)
    end,
    "build endpoint catalogue" => fn %{catalogue: catalogue} ->
      {:ok, _} = EndpointCatalogue.new(catalogue)
    end,
    "discover endpoints through an in-process client" => fn %{session: session} ->
      {:ok, %EndpointCatalogue{}} =
        Wotex.Matter.discover_endpoints(session, Topology.node_identity())
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/endpoint_discovery.md",
     title: "# Matter endpoint discovery on the BEAM side",
     description: """
     The stages of `Wotex.Matter.discover_endpoints/3` over a synthetic bridge
     with 4, 16 and 32 endpoints (root, aggregator and bridged On/Off Lights).
     Discovery reads the four Descriptor attributes of the root endpoint, then
     of the remaining endpoints in batches of 16. `Wotex.Matter.Native.Wire.frame/1`
     admits each batch's native response line under the shared IPC bounds,
     `Wotex.Matter.PathResults.normalize/2` validates and orders each batch,
     and `Wotex.Matter.EndpointCatalogue.new/1` validates the endpoint graph.
     The last job runs the whole facade operation, including Descriptor value
     conversion, against an in-process `Wotex.Matter.Client` that answers from
     prepared reports; no controller, process or network is involved.
     """}
  ]
)
