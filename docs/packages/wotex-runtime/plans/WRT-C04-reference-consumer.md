# WRT-C04: Exact-archive reference consumer

Packet `WRT-C04` verifies Runtime through a separate Mix consumer. The consumer
depends on unpacked contents from exact `wotex_runtime` and `wotex` archives. It
does not compile either dependency from a live source checkout.

Run the lane with the exact core archive supplied explicitly:

```bash
WOTEX_CORE_ARCHIVE=/absolute/path/wotex-0.1.0.tar \
  elixir bin/check_reference_consumer.exs
```

The checker builds the Runtime archive, creates an isolated consumer, resolves
the consumer's dependency graph, verifies its lock, and runs its tests with
warnings as errors. It prints the Runtime archive, core archive, and consumer
lock SHA-256 digests.

The reference consumer supplies its own credential and transport ports. Its
tests establish these observable behaviors:

- loading Runtime defines no application callback;
- ConsumedThing construction and subscription child-spec construction perform
  no port activity;
- short requests execute through the explicit ports and return correlated
  Results;
- malformed and unsupported aggregate operations fail before a port request;
- one subscription delivers and explicitly unsubscribes;
- two independently identified subscriptions coexist under a caller-owned
  supervisor; and
- the caller-selected child shutdown value is retained, invalid values fail,
  and graceful supervisor shutdown requests unsubscription.

This lane establishes exact-archive dependency use and portable Runtime
lifecycle mechanics. The ports are deterministic fixtures. It does not
establish protocol interoperability, native Software Development Kit behavior,
remote cleanup, registry publication, or production acceptance.
