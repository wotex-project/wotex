alias Wotex.DataSchema
alias Wotex.Nx.{Decoder, Observation, OutputSchema, Prediction}

output_schema = fn kind, data_schema ->
  {:ok, schema} =
    OutputSchema.new(
      kind: kind,
      thing_id: "urn:example:thing:bench",
      affordance_type: :property,
      affordance_name: "temperature",
      data_schema: data_schema
    )

  schema
end

inputs =
  Map.new(
    %{"scalar" => nil, "16-step forecast" => 16, "256-step forecast" => 256},
    fn {label, length} ->
      {schema_map, values} =
        case length do
          nil ->
            {%{"type" => "number", "unit" => "Cel"}, 21.5}

          count ->
            {%{
               "type" => "array",
               "items" => %{"type" => "number", "unit" => "Cel"},
               "minItems" => count,
               "maxItems" => count
             }, Enum.map(1..count, &(20.0 + rem(&1, 40) / 8))}
        end

      {:ok, data_schema} = DataSchema.new(schema_map)

      {label,
       %{
         tensor: Nx.tensor(values, type: :f32),
         prediction: output_schema.(:prediction, data_schema),
         observation: output_schema.(:observation, data_schema)
       }}
    end
  )

Benchee.run(
  %{
    "decode :prediction" => fn %{tensor: tensor, prediction: schema} ->
      {:ok, %Prediction{}} =
        Decoder.decode(tensor, schema,
          id: "urn:example:prediction:1",
          produced_at: 0,
          target_at: 60_000
        )
    end,
    "decode :observation" => fn %{tensor: tensor, observation: schema} ->
      {:ok, %Observation{}} =
        Decoder.decode(tensor, schema, id: "urn:example:observation:1", observed_at: 0)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/decoder.md",
     title: "# Decoding numerical output into inert values",
     description: """
     `Wotex.Nx.Decoder.decode/3` of an `f32` tensor on the default
     `Nx.BinaryBackend` into an inert `Wotex.Nx.Prediction` or
     `Wotex.Nx.Observation`, for a scalar `number` DataSchema and fixed-size
     arrays of 16 and 256 numbers. Decoding rechecks the `Wotex.Nx.OutputSchema`,
     the tensor shape and dtype, reads the tensor back to host values and
     validates them against the DataSchema before building the value.
     """}
  ]
)
