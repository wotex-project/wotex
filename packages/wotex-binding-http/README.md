# Wotex HTTP Binding

`wotex_binding_http` maps selected W3C Web of Things TD Forms to HTTP messages
for `wotex_runtime`. A consumer-supplied client performs every network action.
The package contains no concrete client, connection pool, application callback,
supervisor, credential source, database, or web framework.

This package does **not** claim conformance with a W3C WoT Profile or a current
entry in the pilot WoT Binding Registry. See the
[dated standards baseline](docs/standards-baseline.md).

## Installation

Add the released package to `mix.exs`:

```elixir
def deps do
  [
    {:wotex_binding_http, "~> 0.1.0"}
  ]
end
```

Normal builds resolve `wotex ~> 0.1.0` and `wotex_runtime ~> 0.1.0` from Hex.
Maintainers may set `WOTEX_PATH_DEPS=1` to use adjacent local checkouts while
developing this package. The published archive never depends on that switch.

## Client port

The consumer host implements `Wotex.Binding.HTTP.Client`:

```elixir
defmodule ConsumerHTTPClient do
  @behaviour Wotex.Binding.HTTP.Client

  @impl true
  def request(request, credential, config) do
    # Execute the immutable request with the ephemeral credential, then return
    # Wotex.Binding.HTTP.Response.new(status, headers, body).
  end

  @impl true
  def subscribe(request, credential, event_handler, config) do
    # Open one SSE response, parse framing, call event_handler with Event values,
    # and return {:ok, opaque_handle, handshake_response}.
  end

  @impl true
  def close(opaque_handle, config) do
    # Terminate exactly the connection represented by opaque_handle.
  end
end
```

Credentials are a separate immediate callback argument. They never enter the
binding's request, response, result metadata, error, subscription handle, or
notification values. The supplied client must not retain them.

Build the Runtime entries explicitly:

```elixir
{:ok, profile} = Wotex.Binding.HTTP.profile()

{:ok, config} =
  Wotex.Binding.HTTP.config(
    client: {ConsumerHTTPClient, %{transport_options: []}},
    headers: [{"user-agent", "consumer-host"}]
  )

transport = Wotex.Binding.HTTP.transport(config)
```

Pass `profile` in the Runtime profile list and put `transport` under the
profile id `:http`. The consumer host separately supplies the Runtime
credential port.

For an Action with no input, pass `Wotex.Binding.HTTP.empty_body()`. Elixir
`nil` remains the JSON value `null` and is encoded as such.

## Server-Sent Events

Only `observeproperty` and `subscribeevent` Forms with `"subprotocol": "sse"`
open streams. The normal Runtime observation or Event-subscription API returns
a child specification; the caller chooses whether and where to start it.

The client parses SSE framing into `Wotex.Binding.HTTP.SSE.Event` values. The
binding decodes each event's `data` as JSON and the Runtime receiver gets:

```elixir
{:wotex_runtime, subscription_id,
 {:ok, %Wotex.Binding.HTTP.Notification{}}}
```

Malformed or oversized event data is delivered as `{:error, error}` in the
same payload position. `unobserveproperty` and `unsubscribeevent` call
`Client.close/2`; they do not issue a hidden HTTP request.

## Safety boundaries

- Only absolute `http` and `https` targets without user information or
  fragments are accepted.
- Static and `htv:headers` fields are validated case-insensitively. Credential,
  host, connection, and message-framing fields are rejected.
- JSON request, response, and event byte limits are explicit configuration.
- Client errors and exceptions are normalized without retaining external
  reasons.
- Loading the package starts no process.

## Development

```console
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix check
bin/check-boundary
bin/check-archive
```

`mix check` enforces formatting, warnings, at least 90% coverage, documentation,
and a Hex archive build with `WOTEX_PATH_DEPS` removed for archive metadata.

Licensed under Apache-2.0.
