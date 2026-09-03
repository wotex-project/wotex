# Wotex HTTP Binding

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_binding_http.svg)](https://hex.pm/packages/wotex_binding_http)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_binding_http)
[![CI](https://github.com/wotex-project/wotex-binding-http/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-binding-http/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-binding-http/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-binding-http)
[![License](https://img.shields.io/github/license/wotex-project/wotex-binding-http.svg)](LICENSE)

Caller-owned HTTP and Server-Sent Events transport for the Wotex Runtime.

[Documentation](https://hexdocs.pm/wotex_binding_http) ·
[Hex package](https://hex.pm/packages/wotex_binding_http) ·
[Source](https://github.com/wotex-project/wotex-binding-http) ·
[Wotex](https://wotex.io)

`wotex_binding_http` maps selected W3C Web of Things Thing Description (TD)
Forms to immutable HTTP messages. A consumer-supplied client performs every
network action, so the package adds protocol semantics without imposing a
client library, pool, supervision tree, credential store, or deployment model.

The package implements a dated standards baseline. It does **not** claim
conformance with a W3C WoT Profile or registration in the pilot WoT Binding
Registry. See the [standards baseline](docs/standards-baseline.md).

## Why the client is supplied

HTTP ownership is intentionally split at a narrow port:

| The binding owns | The consumer client owns |
| --- | --- |
| TD Form and WoT operation mapping | DNS, sockets, TLS, proxies, and redirects |
| Immutable request and response values | Connection pools and supervision |
| Header safety and JSON byte limits | Deadlines and transport cancellation |
| Runtime result and notification mapping | SSE framing, reconnect, and backpressure |
| Credential-free error normalization | Applying an ephemeral credential to a request |

This keeps network policy in the consumer host while preserving one stable,
testable HTTP meaning for Wotex interactions.

## Installation

Add the package to `mix.exs`:

```elixir
def deps do
  [
    {:wotex_binding_http, "~> 0.1.0"}
  ]
end
```

Normal builds resolve `wotex ~> 0.1.0` and `wotex_runtime ~> 0.1.0` from Hex.
The released archive contains no local path dependencies or agent files.

## Implement the client port

The consumer host implements `Wotex.Binding.HTTP.Client` and chooses the
underlying HTTP library:

```elixir
defmodule ConsumerHTTPClient do
  @behaviour Wotex.Binding.HTTP.Client

  @impl true
  def request(request, credential, config) do
    # Perform one finite request and return:
    # {:ok, response} = Wotex.Binding.HTTP.Response.new(status, headers, body)
  end

  @impl true
  def subscribe(request, credential, event_handler, config) do
    # Open one SSE response, parse framing, call event_handler for each complete
    # Event value, and return {:ok, opaque_handle, handshake_response}.
  end

  @impl true
  def close(opaque_handle, config) do
    # Close exactly the SSE connection represented by opaque_handle.
  end
end
```

The credential is a separate, immediate callback argument. It must never be
retained, logged, included in the opaque handle, captured by the event handler,
or returned in an error. Client configuration must contain no credentials.

## Configure the Runtime transport

```elixir
{:ok, profile} = Wotex.Binding.HTTP.profile()

{:ok, config} =
  Wotex.Binding.HTTP.config(
    client: {ConsumerHTTPClient, %{transport_options: []}},
    headers: [{"user-agent", "consumer-host"}],
    max_request_bytes: 1_048_576,
    max_response_bytes: 4_194_304,
    max_event_bytes: 1_048_576
  )

transport = Wotex.Binding.HTTP.transport(config)
```

Pass `profile` in the Runtime profile list and put `transport` under profile id
`:http`. The consumer host supplies the Runtime credential port separately.

For an Action with no input, pass `Wotex.Binding.HTTP.empty_body()`. Elixir
`nil` remains the JSON value `null` and is encoded as such.

## HTTP mapping

The binding accepts absolute `http` and `https` targets without user information
or fragments. It supports JSON representations and maps these WoT operations:

| Operation | Default method | Body or target behavior |
| --- | --- | --- |
| `readproperty` | `GET` | no body |
| `writeproperty` | `PUT` | JSON input required |
| `invokeaction` | `POST` | JSON input or explicit empty body |
| `queryaction` | `GET` | action target from prior result |
| `cancelaction` | `DELETE` | action target from prior result |
| `observeproperty` | `GET` | SSE stream |
| `subscribeevent` | `GET` | SSE stream |

A single-operation Form may declare `htv:methodName`. Static headers and
`htv:headers` are normalized and composed deterministically. Credential,
connection, host, and message-framing fields are rejected case-insensitively;
the client owns those concerns.

## Server-Sent Events

Only `observeproperty` and `subscribeevent` Forms with `"subprotocol": "sse"`
open streams. Runtime returns a child specification, and the consumer chooses
where and when to supervise it.

The client parses SSE framing into `Wotex.Binding.HTTP.SSE.Event` values. The
binding validates and decodes each event's JSON `data`, then sends the Runtime
receiver:

```elixir
{:wotex_runtime, subscription_id,
 {:ok, %Wotex.Binding.HTTP.Notification{}}}
```

Malformed or oversized event data uses `{:error, error}` in the same payload
position. `unobserveproperty` and `unsubscribeevent` call `Client.close/2`; they
never issue a hidden HTTP request.

## Failure model

Public failures are `Wotex.Binding.HTTP.Error` values with a stable `code`, a
boundary `phase`, a human-readable `message`, and safe `details`. Client reasons
and exceptions are normalized rather than copied, which prevents transport
objects or secrets from crossing the binding boundary.

The package also enforces these invariants:

- Request, response, subscription, notification, and error values contain no credentials.
- Request, response, and event payload limits are measured in encoded bytes.
- Loading the application starts no process and defines no application callback.
- No database, web framework, endpoint, global registry, or built-in client is present.

## Development

Adjacent source checkouts can be selected explicitly for local development:

```console
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix check
```

`mix check` is provided solely by ExCheck. It runs warnings-as-errors,
formatting, unused-dependency checks, strict Credo, dependency audits, Doctor,
Dialyzer, warning-free ExDoc, at least 95% line coverage, architectural boundary
checks, and a clean unpacked-archive compile with a no-callback proof.

Focused proofs remain available as `bin/check-boundary` and
`bin/check-archive`.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
