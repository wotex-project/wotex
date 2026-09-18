Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/interactions.exs", __DIR__)

alias Wotex.Binding.MQTT.Bench.Interactions
alias Wotex.Binding.MQTT.{Error, Transport}

context = Interactions.execution_context()
payload = Interactions.payload(16)
json = Interactions.json(payload)
write = Interactions.request(:property, "state", :writeproperty, payload)
read = Interactions.request(:property, "state", :readproperty, nil)
observe = Interactions.request(:property, "state", :observeproperty, nil)

elapsed =
  Interactions.request(:property, "state", :readproperty, nil,
    deadline: System.monotonic_time(:millisecond) - 60_000
  )

refused = Interactions.config(%{publish: {:error, :not_connected}})
raising = Interactions.config(%{publish: {:raise, "client failed"}})
invalid = Interactions.config(%{publish: :accepted})
small = Interactions.config(%{publish: :ok}, max_payload_bytes: 64)
retained = Interactions.config(%{read: {:ok, Interactions.delivery(json)}})
live = Interactions.config(%{read: {:ok, Interactions.delivery(json, retain: false)}})
malformed = Interactions.delivery(binary_part(json, 0, byte_size(json) - 1), retain: false)

Benchee.run(
  %{
    "refused publish (unavailable)" => fn ->
      {:error, %Error{code: :client_publish_failed, class: :unavailable}} =
        Transport.request(write, context, refused)
    end,
    "raising client (unavailable)" => fn ->
      {:error, %Error{code: :client_publish_failed, class: :unavailable}} =
        Transport.request(write, context, raising)
    end,
    "invalid client return (protocol)" => fn ->
      {:error, %Error{code: :invalid_client_return, class: :protocol}} =
        Transport.request(write, context, invalid)
    end,
    "payload above the limit (protocol)" => fn ->
      {:error, %Error{code: :encoded_payload_too_large, class: :protocol}} =
        Transport.request(write, context, small)
    end,
    "elapsed read deadline (timeout)" => fn ->
      {:error, %Error{code: :deadline_exceeded, class: :timeout}} =
        Transport.request(elapsed, context, retained)
    end,
    "non-retained read delivery (protocol)" => fn ->
      {:error, %Error{code: :non_retained_property_read, class: :protocol}} =
        Transport.request(read, context, live)
    end,
    "truncated JSON delivery (protocol)" => fn ->
      {:error, %Error{code: :json_decode_failed, class: :protocol}} =
        Transport.decode_frame(malformed, observe, retained)
    end
  },
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/errors.md",
     title: "# Failure classification",
     description: """
     The failure paths of `Wotex.Binding.MQTT.Transport` against an in-memory
     client port. Each job asserts the code and retry class of the returned
     `Wotex.Binding.MQTT.Error`: a publish the client refuses, a client that
     raises, a client that returns an undeclared value, a 16-member value above
     a 64-byte payload limit, a retained read whose request deadline has
     elapsed, a read answered by a non-retained delivery, and a truncated JSON
     delivery decoded by `decode_frame/3`.
     """}
  ]
)
