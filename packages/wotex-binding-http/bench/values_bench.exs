alias Wotex.Binding.HTTP.{Headers, Request, Response}

fields = fn count ->
  standard = [
    {"Accept", "application/json"},
    {"User-Agent", "consumer-host"},
    {"X-Correlation-Id", "urn:example:correlation:0001"},
    {"Cache-Control", "no-store"}
  ]

  extension =
    Enum.map(1..max(count - length(standard), 0)//1, fn index ->
      {"X-Trace-Attribute-#{index}", "value-#{index}"}
    end)

  Enum.take(standard, count) ++ extension
end

request_options = [
  request_id: "bench-request-1",
  operation: :readproperty,
  media_type: "application/json",
  stream?: false,
  max_response_bytes: 4_194_304,
  max_event_bytes: 1_048_576
]

static = [{"user-agent", "consumer-host"}]
body = ~s({"value":21.5,"unit":"Cel"})

inputs =
  Enum.map([{"4 fields", 4}, {"16 fields", 16}, {"64 fields", 64}], fn {label, count} ->
    raw = fields.(count)
    {:ok, normalized} = Headers.new(raw, :request)
    {label, %{raw: raw, normalized: normalized}}
  end)

Benchee.run(
  %{
    "Headers.new/2 for a request" => fn %{raw: raw} -> {:ok, _} = Headers.new(raw, :request) end,
    "Headers.new/2 for a response" => fn %{raw: raw} -> {:ok, _} = Headers.new(raw, :response) end,
    "Headers.merge/2 and get/2" => fn %{normalized: normalized} ->
      "application/json" = Headers.get(Headers.merge(static, normalized), "Accept")
    end,
    "Request.new/5" => fn %{normalized: normalized} ->
      {:ok, _} =
        Request.new(
          "GET",
          "https://thing.example/properties/state",
          normalized,
          nil,
          request_options
        )
    end,
    "Response.new/3" => fn %{raw: raw} -> {:ok, _} = Response.new(200, raw, body) end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/values.md",
     title: "# HTTP field and message value construction",
     description: """
     `Wotex.Binding.HTTP.Headers`, `Wotex.Binding.HTTP.Request` and
     `Wotex.Binding.HTTP.Response` over field lists of four, 16 and 64 entries,
     64 being the default field-count limit. Field names are mixed case, so
     construction validates each token and value and lowercases the name.
     `Request.new/5` also applies the field-count, aggregate field-byte and
     URI limits before it normalizes the fields again; `merge/2` and `get/2`
     compose static configuration fields with an already validated list.
     """}
  ]
)
