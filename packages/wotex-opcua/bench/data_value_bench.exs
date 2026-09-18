Code.require_file("support/values.exs", __DIR__)

alias Wotex.OPCUA.Bench.Values
alias Wotex.OPCUA.{Binary, Value}

Benchee.run(
  %{
    "encode DataValue" => fn %{data_value: data_value} ->
      {:ok, _} = Binary.encode_data_value(data_value)
    end,
    "decode DataValue" => fn %{bytes: bytes} -> {:ok, _, <<>>} = Binary.decode_data_value(bytes) end,
    "project native DataValue" => fn %{native: native} ->
      {:ok, _, _} = Value.native_result(native)
    end
  },
  inputs: Values.inputs(),
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/data_value.md",
     title: "# OPC UA DataValue and Variant conversion",
     description: """
     `Wotex.OPCUA.Binary.encode_data_value/1` and `decode_data_value/1` (Part 6
     DataValue with an explicit Variant, StatusCode and source and server
     timestamps) and `Wotex.OPCUA.Value.native_result/1`, which projects the
     native JSON DataValue of a Read or an observation onto a Runtime payload and
     metadata. Inputs are a Double scalar, a flat array of 64 ByteStrings of
     32 bytes each (Base64 in the native form) and a flat Double array at the
     1024-element Variant ceiling.
     """}
  ]
)
