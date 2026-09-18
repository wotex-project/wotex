Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/interactions.exs", __DIR__)

alias Wotex.Matter.Bench.Interactions
alias Wotex.Matter.{Error, Mapping, Transport}
alias Wotex.Runtime.Result

config = Interactions.config()
failing = Interactions.failing_config()

Benchee.run(
  %{
    "map Form to Matter request" => fn %{oneshot: request} ->
      {:ok, _} =
        Mapping.command(request.form, request.operation, request.input, request.resolved_href)
    end,
    "one-shot Transport.request/3" => fn %{oneshot: request, execution: execution} ->
      {:ok, %Result{}} = Transport.request(request, execution, config)
    end,
    "controller Transport.request/3" => fn %{controller: request, execution: execution} ->
      {:ok, %Result{}} = Transport.request(request, execution, config)
    end,
    "classified client failure" => fn %{controller: request, execution: execution} ->
      {:error, %Error{class: class}} = Transport.request(request, execution, failing)
      true = class in [:unavailable, :permanent]
    end
  },
  inputs: Interactions.inputs(),
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/runtime_transport.md",
     title: "# Matter Form mapping and Runtime transport requests",
     description: """
     A Property read (OnOff), a Property write (Thermostat
     OccupiedHeatingSetpoint) and an Action invocation (On/Off Toggle) selected
     from `matter` Forms by `Wotex.Runtime.FormSelector`.
     `Wotex.Matter.Mapping.command/4` maps the Form href to a concrete request.
     The `request/3` callback of `Wotex.Matter.Transport` adds the fabric target
     check, input preflight, deadline budget, session open and close, the client
     call and the Runtime Result, through the one-shot profile and through the
     controller profile, whose typed services validate Descriptor values and
     reports. The client is an in-process `Wotex.Matter.Client` answering from
     prepared values; the failure job has it reject every request with
     `:transport_unavailable`, which the facade classifies (unknown effect for
     writes and invokes).
     """}
  ]
)
