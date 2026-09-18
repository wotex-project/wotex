# Wotex HTTP Binding

**Caller-owned HTTP and Server-Sent Events transport for Wotex Runtime.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_binding_http.svg)](https://hex.pm/packages/wotex_binding_http)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_binding_http)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_binding_http.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-http/LICENSE)

[Documentation](https://hexdocs.pm/wotex_binding_http) ·
[Hex package](https://hex.pm/packages/wotex_binding_http) ·
[Source](https://github.com/wotex-project/wotex/tree/main/packages/wotex-binding-http) ·
[Wotex](https://wotex.io)

---

This is the `0.1.0` stable API candidate in a development checkout. No published
release or W3C certification is implied.

`wotex_binding_http` maps selected W3C Web of Things Thing Description (TD)
Forms to immutable HTTP messages. A consumer-supplied client performs every
network action, so the package adds protocol semantics without imposing a
client library, pool, supervision tree, credential store, or deployment model.

The package implements a dated standards baseline. It does **not** claim
conformance with a W3C WoT Profile or registration in the pilot WoT Binding
Registry. See the [standards baseline](../../docs/packages/wotex-binding-http/standards-baseline.md).

## Why the client is supplied

HTTP ownership is intentionally split at a narrow port:

| The binding owns | The consumer client owns |
| --- | --- |
| TD Form and WoT operation mapping | DNS, sockets, TLS, proxies, and redirects |
| Immutable request and response values | Connection pools and supervision |
| Header, URI, and JSON admission limits | Deadlines and transport cancellation |
| Runtime result and delivery mapping | SSE framing, reconnect, and backpressure |
| Credential-free error normalization | Applying an ephemeral credential to a request |

This keeps network policy in the consumer host while preserving one stable,
testable HTTP meaning for Wotex interactions.

## Installation

Wotex HTTP Binding 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through
Elixir 1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
No version is published on Hex yet. Once one is, depend on it as usual; Hex
resolves `wotex` and `wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [
    {:wotex_binding_http, "~> 0.1"}
  ]
end
```

Until then, depend on one commit of the
[WoTEx repository](https://github.com/wotex-project/wotex) and select each
package directory with `sparse:`. The binding's `mix.exs` declares Hex
requirements for `wotex` and `wotex_runtime`, so declare all three packages at
the same `ref` with `override: true`, as the
[consumer guide](https://github.com/wotex-project/wotex/blob/main/docs/guides/consumer.md)
describes:

```elixir
@wotex_ref "<commit>"

def deps do
  [
    {:wotex,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex",
     override: true},
    {:wotex_runtime,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-runtime",
     override: true},
    {:wotex_binding_http,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-binding-http",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true},
{:wotex_binding_http, path: "../wotex/packages/wotex-binding-http", override: true}
```

Path dependencies prove nothing about a released artifact. The package's
archive check rejects Git and path dependencies and agent files in the
packaged source.

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

Each request carries response/event byte, field-count, aggregate field-byte,
and URI-byte ceilings so the client can abort oversized input while reading it,
plus an absolute `deadline` the client honors with its own clock reading. An
integer deadline is a `System.monotonic_time(:millisecond)` point and a
`DateTime` is UTC; use `Wotex.Runtime.Context.remaining_ms/2` for the remaining
budget. A client that expires a call returns `{:error, :timeout}`, the single
reason the binding interprets.

The client and consumer host authorize the final request target, each DNS/IP
result, proxy route, and every redirect before I/O. Apply an ephemeral
credential only while the exact target remains inside its audience. URI syntax
and length checks in this package are not SSRF protection, redirect policy, or
credential authorization.

## Configure the Runtime transport

```elixir
{:ok, profile} = Wotex.Binding.HTTP.profile()

{:ok, config} =
  Wotex.Binding.HTTP.config(
    client: {ConsumerHTTPClient, %{transport_options: []}},
    headers: [{"user-agent", "consumer-host"}],
    max_request_bytes: 1_048_576,
    max_response_bytes: 4_194_304,
    max_event_bytes: 1_048_576,
    max_header_count: 64,
    max_header_bytes: 65_536,
    max_uri_bytes: 8_192
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

The [HTTP operation inventory](../../docs/packages/wotex-binding-http/http-operation-inventory.md) records the
complete nine-operation open/close matrix, the unsupported aggregate cell,
exact authorities, and named positive/negative vectors.

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

The [client and SSE lifecycle inventory](../../docs/packages/wotex-binding-http/client-lifecycle-inventory.md)
maps callback failures, handshake cleanup, close concurrency, configuration
identity, and owner failure to named vectors. It also identifies
pending-establishment owner monitoring as a supplied-client obligation.

The [exact archive and reference-consumer inventory](../../docs/packages/wotex-binding-http/reference-consumer-inventory.md)
maps the isolated three-archive installation, finite request, redirect/audience,
limit, supervised SSE and failure-redaction vectors. The generated consumer and
run artifacts remain outside this repository.

The [limits and security inventory](../../docs/packages/wotex-binding-http/limits-security-inventory.md) records
exact thresholds, native JSON admission, sustained receiver overload, deadline
and destination policy seams, redaction vectors, and the remaining client-owned
nonclaims.

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
- Request, response, and event payload limits are measured in encoded bytes; fields and URIs have separate explicit admission ceilings, and JSON uses bounded `Wotex.JSON` admission.
- Loading the application starts no process and defines no application callback.
- No database, web framework, endpoint, global registry, or built-in client is present.

## Development

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-binding-http test test/wotex/binding/http/form_test.exs  # one test file
mix check.fast --package wotex-binding-http                            # compile, format, Credo, tests
mix pkg wotex-binding-http check --no-retry                            # full gate
```

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-binding-http`. It compiles with warnings as errors, checks the
lock and unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
tests with the coverage floor (`mix coveralls`), Dialyzer, the public
boundary scan (`elixir bin/check_boundary.exs`) and `git diff --check`, and
then runs the exact-archive check
(`mix run --no-start bin/check_archive.exs`). That check builds the `wotex`,
`wotex_runtime` and `wotex_binding_http` archives from `packages/` without
path dependencies, inspects their contents and runs an isolated reference
consumer against the unpacked artifacts.

The local toolchain is the Elixir and Erlang/OTP pair pinned in the root
`mise.toml`; CI also runs the gate on the minimum pair declared in
`tooling/packages.yaml`. The broader `elixir: "~> 1.18"` package requirement is
not a tested runtime matrix. The gate uses the `wotex` and `wotex-runtime`
packages from the same commit. This package has no native build, software
profile, interop or container lane.

The boundary and exact-archive commands are focused proofs. The
[public release-candidate inventory](../../docs/packages/wotex-binding-http/release-candidate-inventory.md)
documents package metadata, legal/security, dependency, documentation,
toolchain, and remaining publication-order evidence.

## License

Apache-2.0. See [LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-http/LICENSE)
and [NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-http/NOTICE).
