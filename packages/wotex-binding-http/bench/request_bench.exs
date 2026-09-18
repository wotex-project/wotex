Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/interactions.exs", __DIR__)

alias Wotex.Binding.HTTP.Bench.Interactions
alias Wotex.Binding.HTTP.{Codec, Transport}

max_bytes = Interactions.max_bytes()
context = Interactions.execution_context()

inputs =
  Enum.map(Interactions.sizes(), fn {label, count} ->
    payload = Interactions.payload(count)
    json = Interactions.json(payload)
    json_fields = [{"content-type", "application/json"}]

    replies = %{
      readproperty: {:ok, Interactions.response(200, json_fields, json)},
      writeproperty: {:ok, Interactions.response(204, [], "")},
      invokeaction:
        {:ok,
         Interactions.response(
           201,
           [{"location", "/actions/adjust/status/7"} | json_fields],
           ~s({"status":"pending"})
         )}
    }

    {label,
     %{
       payload: payload,
       json: json,
       config: Interactions.config(replies),
       read: Interactions.request(:property, "state", :readproperty, nil),
       write: Interactions.request(:property, "state", :writeproperty, payload),
       invoke: Interactions.request(:action, "adjust", :invokeaction, payload)
     }}
  end)

Benchee.run(
  %{
    "Codec.encode/2" => fn %{payload: payload} -> {:ok, _} = Codec.encode(payload, max_bytes) end,
    "Codec.decode/2" => fn %{json: json} -> {:ok, _} = Codec.decode(json, max_bytes) end,
    "readproperty: GET and decode" => fn %{read: request, config: config} ->
      {:ok, _} = Transport.request(request, context, config)
    end,
    "writeproperty: encode and PUT" => fn %{write: request, config: config} ->
      {:ok, _} = Transport.request(request, context, config)
    end,
    "invokeaction: encode, POST and resolve Location" => fn %{invoke: request, config: config} ->
      {:ok, _} = Transport.request(request, context, config)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/request.md",
     title: "# Form mapping and finite request round trips",
     description: """
     The `c:Wotex.Runtime.Transport.request/3` callback of
     `Wotex.Binding.HTTP.Transport` for Runtime requests selected from a
     synthetic Thing Description, against an in-memory client that returns a
     prepared `Wotex.Binding.HTTP.Response`. Each round trip maps the Form to a
     `Wotex.Binding.HTTP.Request`, calls the client, revalidates the response
     fields and builds the Runtime result. The Property value and Action input
     is a JSON object with one, 16 or 256 members; `readproperty` decodes it
     from a 200 response, `writeproperty` encodes it and receives 204, and
     `invokeaction` encodes it, uses an explicit `htv:methodName` and
     `htv:headers`, and resolves the `Location` of a 201 response.
     `Wotex.Binding.HTTP.Codec` alone is the bounded JSON baseline.
     """}
  ]
)
