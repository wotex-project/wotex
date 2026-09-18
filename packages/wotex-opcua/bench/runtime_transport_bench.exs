Code.require_file("support/values.exs", __DIR__)
Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/interactions.exs", __DIR__)

alias Wotex.OPCUA.Bench.Interactions
alias Wotex.OPCUA.{Error, Mapping, Transport}
alias Wotex.Runtime.Result

config = Interactions.config()
failing = Interactions.failing_config()

Benchee.run(
  %{
    "map Form to OPC UA request" => fn %{request: request} ->
      {:ok, _} =
        Mapping.command(request.form, request.operation, request.input, request.resolved_href)
    end,
    "transport request through an in-process client" => fn input ->
      {:ok, %Result{}} = Transport.request(input.request, input.execution, config)
    end,
    "classified client failure" => fn input ->
      {:error, %Error{class: class}} = Transport.request(input.request, input.execution, failing)
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
     title: "# OPC UA Form mapping and Runtime transport requests",
     description: """
     A Property read of a Double, a Property write of a Double declared by the
     Form's `wotex:variantType`, and a Property write of an explicitly typed flat
     array of 16 ByteStrings of 64 bytes, each selected from an `opc.tcp` Form
     by `Wotex.Runtime.FormSelector` through the one-shot profile.
     `Wotex.OPCUA.Mapping.command/4` parses the endpoint and NodeId and converts
     write input to a typed Variant. The `request/3` callback of
     `Wotex.OPCUA.Transport` adds the target check, deadline budget, session open
     and close, the client call, DataValue or status projection and the Runtime
     Result. The client is an in-process `Wotex.OPCUA.Client` answering from
     prepared values; the failure job has it reject every request with
     `:connection_failed`, which the transport classifies with
     `Wotex.OPCUA.Error.classify/1` (unknown effect for writes).
     """}
  ]
)
