# Wotex Runtime

**Caller-owned ConsumedThing and ExposedThing mechanics for Elixir.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_runtime.svg)](https://hex.pm/packages/wotex_runtime)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_runtime)
[![CI](https://github.com/wotex-project/wotex-runtime/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-runtime/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-runtime/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-runtime)
[![License](https://img.shields.io/hexpm/l/wotex_runtime.svg)](LICENSE)

[Installation](#installation) ·
[Quick start](#quick-start) ·
[Execution model](#execution-model) ·
[Consumer ports](#consumer-ports) ·
[Subscriptions](#subscriptions) ·
[Boundary](#boundary) ·
[Development](#development)

---

Wotex Runtime turns the values in `wotex` into explicit interaction plans. It
constructs ConsumedThings and ExposedThings, selects compatible Forms and
binding profiles deterministically, resolves credentials through a consumer
port, and delegates protocol exchange to a consumer-supplied transport.

The package does not start an application callback or own a singleton. Ordinary
Property and Action operations run in the caller. Long-lived observations and
Event subscriptions are returned as child specifications so the consumer
chooses their supervision, names, restart policy, and multiplicity.

## Installation

Wotex Runtime 0.1 requires Elixir 1.18 or later.

```elixir
def deps do
  [
    {:wotex_runtime, "~> 0.1.0"}
  ]
end
```

## Quick start

Build a binding profile and a ConsumedThing from an already validated Thing
Description:

```elixir
{:ok, profile} =
  Wotex.Runtime.BindingProfile.new(
    id: :https,
    schemes: ["https"],
    operations: [:readproperty, :writeproperty, :invokeaction],
    media_types: ["application/json"]
  )

{:ok, consumed} =
  Wotex.Runtime.ConsumedThing.new(td,
    profiles: [profile],
    transports: %{:https => {MyTransport, transport_options}},
    credentials: {MyCredentials, credential_options}
  )

context =
  Wotex.Runtime.Context.new!(
    request_id: "request-018f",
    deadline: System.monotonic_time(:millisecond) + 5_000,
    metadata: %{trace_id: "trace-42"}
  )

{:ok, result} =
  Wotex.Runtime.ConsumedThing.read_property(consumed, "temperature", context)
```

The consumer creates request identifiers and deadlines. Wotex Runtime does not
read a clock, generate identity, or infer a default transport.

## Execution model

Each synchronous operation follows one visible path:

```text
Thing Description + operation
  -> deterministic Form and binding-profile selection
  -> credential-free protocol request
  -> just-in-time consumer credential resolution
  -> consumer transport call
  -> typed protocol result
```

Supported operation atoms are available from `Wotex.Runtime.operations/0` and
use the TD 1.1 operation vocabulary. A Form has to declare the requested
operation explicitly; the selector does not guess defaults.

Form selection proves only that the declarations are compatible. It does not
authorize the interaction. Likewise, a successful transport result proves the
declared protocol exchange, not canonical Property truth or a physical Action
effect.

## Consumer ports

Credential providers implement `Wotex.Runtime.Credentials`:

```elixir
defmodule MyCredentials do
  @behaviour Wotex.Runtime.Credentials

  @impl true
  def resolve(security, form, context, options) do
    # Resolve from consumer-owned custody without adding the material to `context`.
    {:ok, lookup_credential(security, form, context, options)}
  end
end
```

Transports implement `Wotex.Runtime.Transport` and receive the typed request,
an ephemeral execution context, and their consumer configuration:

```elixir
defmodule MyTransport do
  @behaviour Wotex.Runtime.Transport

  @impl true
  def request(request, execution_context, options) do
    # Execute the protocol exchange and return a Wotex.Runtime.Result.
    exchange(request, execution_context, options)
  end

  @impl true
  def subscribe(request, receiver, execution_context, options) do
    subscribe_transport(request, execution_context, receiver, options)
  end

  @impl true
  def unsubscribe(handle, request, execution_context, options) do
    unsubscribe_transport(handle, request, execution_context, options)
  end
end
```

Credential material is resolved immediately before the port call. It is not
stored in a Thing Description, binding profile, request, public error, or
subscription state.

## ExposedThings

An ExposedThing dispatches only a handler registered for the exact operation
and Interaction Affordance name:

```elixir
handlers = %{
  {:readproperty, "temperature"} => fn _input, context ->
    {:ok, read_temperature(context)}
  end,
  {:invokeaction, "calibrate"} => fn input, context ->
    calibrate(input, context)
  end
}

{:ok, exposed} = Wotex.Runtime.ExposedThing.new(td, handlers)

Wotex.Runtime.ExposedThing.dispatch(
  exposed,
  :readproperty,
  "temperature",
  nil,
  context
)
```

The consumer remains responsible for authenticating and authorizing the caller
before dispatch.

## Subscriptions

Observations and Event subscriptions return ordinary OTP child specifications:

```elixir
{:ok, child_spec} =
  Wotex.Runtime.ConsumedThing.observation_child_spec(
    consumed,
    "temperature",
    context,
    id: {:temperature, "machine-1"},
    name: MyConsumer.TemperatureObservation,
    receiver: self(),
    restart: :transient
  )

Supervisor.start_child(MyConsumer.Supervisor, child_spec)
```

Constructing the specification starts zero processes and performs no credential
or transport work. The child resolves credentials when it starts, forwards
transport values to the configured receiver, and requests protocol
unsubscription when stopped normally.

## Standards baseline

Operation shapes follow the
[W3C Web of Things Scripting API Group Note](https://www.w3.org/TR/wot-scripting-api/)
dated 3 October 2023 and operate on Thing Description 1.1 values from `wotex`.
This package does not claim Scripting API conformance.

## Boundary

Wotex Runtime owns portable interaction planning and explicit runtime port
contracts. A consumer owns:

- persistence, canonical observations, Action-effect evidence, and transactions;
- authorization, tenancy, entitlement, and safety policy;
- credential custody and concrete transport implementations;
- supervision topology, retry scheduling, queues, and delivery guarantees; and
- protocol-specific semantics not declared by an installed binding profile.

No database, endpoint, queue, provider implementation, or application callback
belongs in this package.

## Development

During coordinated source development, point the runtime at a sibling Wotex
checkout explicitly:

```bash
WOTEX_PATH_DEPS=1 mix setup
WOTEX_PATH_DEPS=1 mix test
WOTEX_PATH_DEPS=1 mix check
WOTEX_PATH_DEPS=1 mix docs
```

`mix check` compiles with warnings as errors, checks formatting and strict
Credo, requires at least 95% line coverage, audits dependencies, runs Doctor and
Dialyzer, builds HexDocs, scans the runtime boundary, and inspects the unpacked
Hex package. CI tests locked and latest allowed dependency graphs at the
supported floor and current toolchains.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before
widening an operation, port, or lifecycle contract.

## License

Wotex Runtime is released under Apache-2.0. See [LICENSE](LICENSE).
