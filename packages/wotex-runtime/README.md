# Wotex Runtime

Wotex Runtime implements caller-owned ConsumedThing and ExposedThing mechanics
over the values defined by `wotex`. It plans Interaction Affordance operations,
selects Forms and binding profiles deterministically, resolves credentials
through a consumer port, and invokes a consumer-supplied transport.

The package owns no database, authorization policy, credential store, transport
connection, physical-device truth, or canonical Property and Action-effect
state. A successful transport result proves only the declared protocol exchange.

Loading the dependency starts no process. Short operations execute in the
caller process. Long-lived subscriptions expose explicit child specifications;
the consumer chooses names, supervision placement, restart policy, and
multiplicity.

```elixir
{:ok, consumed} = Wotex.Runtime.ConsumedThing.new(td,
  profiles: [profile],
  transports: %{profile.id => {Transport, transport_config}},
  credentials: {Credentials, credential_config}
)

context = Wotex.Runtime.Context.new!(request_id: "request-1")
{:ok, result} = Wotex.Runtime.ConsumedThing.read_property(consumed, "temperature", context)
```

The APIs are aligned with the operation shape of the W3C WoT Scripting API
Group Note dated 3 October 2023. This package does not claim Scripting API
conformance.
