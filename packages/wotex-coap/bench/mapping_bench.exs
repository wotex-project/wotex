Code.require_file("support/messages.exs", __DIR__)

alias Wotex.CoAP.Bench.Messages
alias Wotex.CoAP.{Codec, Mapping}

token = Messages.token()
json = Messages.json_format()

# Forms of the draft CoAP profile. Hosts use the 192.0.2.0/24 documentation
# range; no socket is opened.
cases = [
  {"readproperty, number",
   %{
     "href" => "coap://192.0.2.10/properties/temperature",
     "op" => "readproperty",
     "contentType" => "application/json",
     "vendor:calibration" => %{"offset" => 0.5}
   }, :readproperty, nil, 69, "21.5"},
  {"writeproperty, 16-member object",
   %{
     "href" => "coap://192.0.2.10:5683/properties/configuration?revision=7",
     "op" => "writeproperty",
     "cov:confirmable" => true
   }, :writeproperty, Messages.object(16), 68, ""},
  {"invokeaction, 48-member object",
   %{
     "href" => "coap://192.0.2.10/actions/calibrate",
     "op" => "invokeaction",
     "cov:method" => "POST"
   }, :invokeaction, Messages.object(48), 69, Messages.json(48)}
]

inputs =
  Map.new(cases, fn {label, map, operation, input, code, payload} ->
    {:ok, form} = Wotex.Form.new(map)
    {:ok, mapping} = Mapping.command(form, operation, input)
    options = if payload == "", do: [], else: [{12, Codec.uint(json)}]
    {:ok, reply} = Codec.encode(Messages.reply(code, options, payload))

    {label,
     %{
       form: form,
       operation: operation,
       input: input,
       request: %{mapping.message | message_id: 0x7D34, token: token},
       mapping: mapping,
       reply: reply
     }}
  end)

Benchee.run(
  %{
    "map Form to request" => fn %{form: form, operation: operation, input: input} ->
      {:ok, _} = Mapping.command(form, operation, input)
    end,
    "encode request datagram" => fn %{request: request} -> {:ok, _} = Codec.encode(request) end,
    "decode response and value" => fn %{mapping: mapping, reply: reply} ->
      {:ok, message} = Codec.decode(reply)
      {:ok, _} = Mapping.decode(mapping, message)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/mapping.md",
     title: "# Form mapping and representation conversion",
     description: """
     `Wotex.CoAP.Mapping.command/4` over three Forms of the draft CoAP profile:
     a JSON `readproperty` GET with an unknown extension term, a confirmable
     `writeproperty` PUT of a 16-member JSON object with a Uri-Query, and an
     `invokeaction` POST of a 48-member object. Mapping validates the Form and
     operation, the `coap` endpoint and the content format, encodes the input as
     JSON and builds the request options. The request is then encoded with
     `Wotex.CoAP.Codec.encode/1`, and the reply (2.05 with the number, 2.04
     without a payload, 2.05 with a 48-member object) is decoded with
     `Wotex.CoAP.Codec.decode/1` and converted with
     `Wotex.CoAP.Mapping.decode/2`.
     """}
  ]
)
