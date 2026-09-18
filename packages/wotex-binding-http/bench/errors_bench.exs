Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/interactions.exs", __DIR__)

alias Wotex.Binding.HTTP.Bench.Interactions
alias Wotex.Binding.HTTP.{Error, Transport}
alias Wotex.Binding.HTTP.SSE.Event

context = Interactions.execution_context()
read = Interactions.request(:property, "state", :readproperty, nil)
observe = Interactions.request(:property, "state", :observeproperty, nil)
problem = [{"content-type", "application/problem+json"}]
problem_body = ~s({"title":"request failed"})

status = fn code ->
  Interactions.config(%{
    readproperty: {:ok, Interactions.response(code, problem, problem_body)}
  })
end

timeout = Interactions.config(%{readproperty: {:error, :timeout}})
raising = Interactions.config(%{readproperty: {:raise, "client failed"}})

invalid_json =
  Interactions.config(%{
    readproperty:
      {:ok, Interactions.response(200, [{"content-type", "application/json"}], "{\"value\":")}
  })

[s408, s429, s503, s404] = Enum.map([408, 429, 503, 404], status)

small_events = Interactions.config(%{}, max_event_bytes: 64)
{:ok, large_event} = Event.new(Interactions.json(Interactions.payload(16)))

Benchee.run(
  %{
    "status 408 (timeout)" => fn ->
      {:error, %Error{code: :http_status, class: :timeout}} =
        Transport.request(read, context, s408)
    end,
    "status 429 (rate_limited)" => fn ->
      {:error, %Error{code: :http_status, class: :rate_limited}} =
        Transport.request(read, context, s429)
    end,
    "status 503 (unavailable)" => fn ->
      {:error, %Error{code: :http_status, class: :unavailable}} =
        Transport.request(read, context, s503)
    end,
    "status 404 (permanent)" => fn ->
      {:error, %Error{code: :http_status, class: :permanent}} =
        Transport.request(read, context, s404)
    end,
    "client deadline expiry (timeout)" => fn ->
      {:error, %Error{code: :client_request_failed, class: :timeout}} =
        Transport.request(read, context, timeout)
    end,
    "raising client (unavailable)" => fn ->
      {:error, %Error{code: :client_request_exception, class: :unavailable}} =
        Transport.request(read, context, raising)
    end,
    "truncated JSON body (protocol)" => fn ->
      {:error, %Error{code: :json_decode_failed, class: :protocol}} =
        Transport.request(read, context, invalid_json)
    end,
    "oversized SSE event (protocol)" => fn ->
      {:error, %Error{code: :sse_event_too_large, class: :protocol}} =
        Transport.decode_frame(large_event, observe, small_events)
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
     The failure paths of `Wotex.Binding.HTTP.Transport` for a `readproperty`
     request against an in-memory client, and of `decode_frame/3` for an
     `observeproperty` stream. Each job asserts the code and retry class of
     the returned `Wotex.Binding.HTTP.Error`: HTTP statuses 408, 429, 503 and
     404, a client that reports a deadline expiry, a client that raises, a
     truncated JSON response body, and an event above a 64-byte event limit.
     """}
  ]
)
