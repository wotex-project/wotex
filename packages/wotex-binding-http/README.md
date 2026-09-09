# Wotex HTTP Binding

**Caller-owned HTTP and Server-Sent Events transport for Wotex Runtime.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_binding_http.svg)](https://hex.pm/packages/wotex_binding_http)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_binding_http)
[![CI](https://github.com/wotex-project/wotex-binding-http/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-binding-http/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-binding-http/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-binding-http)
[![License](https://img.shields.io/hexpm/l/wotex_binding_http.svg)](https://github.com/wotex-project/wotex-binding-http/blob/main/LICENSE)

[Documentation](https://hexdocs.pm/wotex_binding_http) ·
[Hex package](https://hex.pm/packages/wotex_binding_http) ·
[Source](https://github.com/wotex-project/wotex-binding-http) ·
[Wotex](https://wotex.io)

---

This is a development checkout. The public API remains unstable; no published
release or W3C certification is implied.

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
| Runtime result and delivery mapping | SSE framing, reconnect, and backpressure |
| Credential-free error normalization | Applying an ephemeral credential to a request |

This keeps network policy in the consumer host while preserving one stable,
testable HTTP meaning for Wotex interactions.

## Installation

For a sibling-checkout consumer, select the package explicitly:

```elixir
def deps do
  [
    {:wotex_binding_http, path: "../wotex-binding-http"}
  ]
end
```

Package builds resolve `wotex ~> 0.1.0` and `wotex_runtime ~> 0.1.0` from Hex.
Once a suitable release is available, replace the consumer's path dependency
with its version constraint. Archive checks reject local path dependencies and
agent files in the packaged source.

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
  def subscribe(request, credential, owner, config) do
    # Open one SSE response and parse framing. Send every complete Event value
    # to the Runtime subscription process as {:wotex_transport_frame, event},
    # optionally report {:wotex_transport_status, :reconnected | :session_lost |
    # :transport_down}, and return {:ok, opaque_handle, handshake_response}.
    # The client does not JSON-decode event data. Monitor owner and close the
    # exact connection on DOWN, including while establishment is pending.
  end

  @impl true
  def close(opaque_handle, config) do
    # Close exactly the SSE connection represented by opaque_handle.
  end
end
```

The credential is a separate, immediate callback argument. It must never be
retained, logged, included in the opaque handle, captured by a connection
process, or returned in an error. Client configuration must contain no
credentials.

Each request carries `max_response_bytes` and `max_event_bytes` so the client
can abort an oversized body or event while reading it, and an absolute
`deadline` the client honors with its own clock reading. An integer deadline is
a `System.monotonic_time(:millisecond)` point and a `DateTime` is UTC; use
`Wotex.Runtime.Context.remaining_ms/2` for the remaining budget. A client that
expires a call returns `{:error, :timeout}`, the single reason the binding
interprets.

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

The client parses SSE framing into `Wotex.Binding.HTTP.SSE.Event` values and
sends each one to the subscription process it received as `owner`. Decoding
happens in that process, not on the client's connection: the binding checks the
event byte limit and decodes the JSON `data`, and the Runtime receiver observes

```elixir
{:wotex_runtime, subscription_id, {:ok, data, meta}}
```

where `meta` is `%{event: ..., id: ..., retry: ..., request_id: ..., operation: ...}`.
A frame with empty data is a keep-alive and produces no delivery. Malformed or
oversized event data becomes
`{:wotex_runtime, subscription_id, {:error, %Wotex.Runtime.Error{code: :undecodable_frame}}}`,
and a client session status becomes `{:status, :reconnected | :session_lost |
:transport_down}`. `unobserveproperty` and `unsubscribeevent` call
`Client.close/2`; they never issue a hidden HTTP request.

## Failure model

Public failures are `Wotex.Binding.HTTP.Error` values with a stable `code`, a
boundary `phase`, a retry `class`, a human-readable `message`, and safe
`details`. Client reasons, exceptions, exits, and throws are normalized rather
than copied, which prevents transport objects or secrets from crossing the
binding boundary.

The class feeds `Wotex.Runtime.Retry.decision/3`: status 408 and a client
timeout are `:timeout`, 429 is `:rate_limited`, 502, 503, 504 and any failing
client call are `:unavailable`, codec, representation, handshake, and
client-contract failures are `:protocol`, and everything else is `:permanent`.
Only the first three are retryable, and only for an operation the consumer
admits as idempotent.

The package also enforces these invariants:

- Request, response, subscription, delivery, and error values contain no credentials.
- Request, response, and event payload limits are measured in encoded bytes and JSON decoding runs through the bounded `Wotex.JSON` admission limits.
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

Focused proofs remain available as `bin/check_boundary.exs` and
`bin/check_archive.exs`.

## License

Apache-2.0. See [LICENSE](https://github.com/wotex-project/wotex-binding-http/blob/main/LICENSE)
and [NOTICE](https://github.com/wotex-project/wotex-binding-http/blob/main/NOTICE).
