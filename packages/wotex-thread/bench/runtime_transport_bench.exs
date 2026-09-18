Code.require_file("support/client.exs", __DIR__)

alias Wotex.Runtime.{BindingProfile, Context, ExecutionContext, FormSelector, Request, Result}
alias Wotex.Thread.{Mapping, Transport}

properties = %{"role" => "state", "rloc16" => "rloc16", "networkName" => "network-name"}

{:ok, td} =
  Wotex.ThingDescription.from_map(%{
    "@context" => Wotex.td_context_1_1(),
    "id" => "urn:example:thread:mesh",
    "title" => "Benchmark Thread node",
    "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
    "security" => "nosec_sc",
    "properties" =>
      Map.new(properties, fn {name, path} ->
        {name,
         %{
           "readOnly" => true,
           "forms" => [%{"href" => "thread+unix://mesh/#{path}", "op" => "readproperty"}]
         }}
      end)
  })

{:ok, profile} =
  BindingProfile.new(
    id: :thread,
    schemes: ["thread+unix"],
    operations: [:readproperty],
    media_types: []
  )

context = Context.new!(request_id: "bench-request-1")
execution = ExecutionContext.new(context, nil)
config = [client: Wotex.Thread.Bench.Client, target: "mesh", timeout: 5_000]

inputs =
  Map.new(properties, fn {name, path} ->
    {:ok, selection} = FormSelector.select(td, :property, name, :readproperty, [profile])
    {path, Request.from_selection(selection, context, nil)}
  end)

Benchee.run(
  %{
    "map Form to management request" => fn request ->
      {:ok, _} =
        Mapping.command(request.form, request.operation, request.input, request.resolved_href)
    end,
    "transport request through an in-process client" => fn request ->
      {:ok, %Result{}} = Transport.request(request, execution, config)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/runtime_transport.md",
     title: "# Thread Form mapping and Runtime transport requests",
     description: """
     Read-only Property reads of the device role, RLOC16 and network name,
     selected from `thread+unix` Forms by `Wotex.Runtime.FormSelector` with a
     binding profile declared by the benchmark (the package defines none).
     `Wotex.Thread.Mapping.command/4` maps the Form href to a management
     request and its controller target. The `request/3` callback of
     `Wotex.Thread.Transport` adds the target check, deadline budget, session
     open and close, request validation in `Wotex.Thread.send/2` and the
     Runtime Result. The client is an in-process `Wotex.Thread.Client`
     answering from prepared values; no daemon socket is opened.
     """}
  ]
)
