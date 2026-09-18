Code.require_file("support/values.exs", __DIR__)

alias WotexContinuum.Bench.Values
alias WotexContinuum.{Codec, ObservationProposal}

inputs =
  Map.new(
    %{"scalar value" => nil, "64-sample value" => 64, "1,024-sample value" => 1_024},
    fn {label, count} ->
      map = Values.observation_proposal(count)
      {:ok, value} = WotexContinuum.from_map(map)
      {:ok, json} = Codec.encode(value)
      {label, %{map: map, value: value, json: json}}
    end
  )

Benchee.run(
  %{
    "Codec.decode" => fn %{json: json} ->
      {:ok, %ObservationProposal{}} = Codec.decode(json)
    end,
    "Codec.encode" => fn %{value: value} -> {:ok, _} = Codec.encode(value) end,
    "Codec.encode canonical" => fn %{value: value} ->
      {:ok, _} = Codec.encode(value, canonical: true)
    end,
    "WotexContinuum.from_map (decoded map)" => fn %{map: map} ->
      {:ok, %ObservationProposal{}} = WotexContinuum.from_map(map)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/codec.md",
     title: "# Bounded decoding and canonical encoding",
     description: """
     `WotexContinuum.Codec` over an `observation_proposal` at wire schema 2.0.0
     with a nested `execution_scope` and `mode`, whose Property value is a scalar
     or a sampled series of 64 or 1,024 numbers. Decoding applies the default
     `WotexContinuum.Limits` through `Wotex.JSON.decode/2` and then constructs
     the value; both encodings revalidate the value first, and the canonical
     form orders object members by UTF-8 bytes. `WotexContinuum.from_map/1`
     measures construction from an already decoded string-keyed map.
     """}
  ]
)
