Code.require_file("support/values.exs", __DIR__)
Code.require_file("support/native_lines.exs", __DIR__)

alias Wotex.OPCUA.Bench.NativeLines
alias Wotex.OPCUA.Native.Frame

generation = NativeLines.generation()

Benchee.run(
  %{
    "encode request line" => fn input ->
      {:ok, _} = Frame.request(generation, input.id, input.operation, input.parameters, 5_000, 1)
    end,
    "classify output line" => fn %{id: id, response: line} ->
      {:response, ^id} = Frame.classify(line, generation)
    end,
    "decode correlated response" => fn input ->
      {:ok, _} = Frame.response(input.response, generation, input.id, input.operation, 60_000)
    end
  },
  inputs: NativeLines.inputs(),
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/native_frame.md",
     title: "# OPC UA native JSON-line framing",
     description: """
     `Wotex.OPCUA.Native.Frame` on the BEAM side of the native executable's
     JSON-line protocol: `request/6` encodes and bounds one version-1 request
     line, `classify/2` admits one output line under the IPC limits and reads
     its correlation, and `response/5` admits the line again and validates the
     operation's result. Inputs are a Read of a Double DataValue, one Browse
     page of 64 typed references and a Session open whose request carries
     synthetic credential envelopes of typical DER sizes and whose response
     carries a NamespaceArray of 32 URIs.
     """}
  ]
)
