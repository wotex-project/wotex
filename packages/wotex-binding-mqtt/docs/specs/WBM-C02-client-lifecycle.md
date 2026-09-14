# WBM-C02: Client lifecycle and recovery proof

Completion packet `WBM-C02`; package baseline `wotex_binding_mqtt 0.1.0`.
Requires `WBM-C01` and the `WBM.03` Runtime transport contract.

## Proven boundary

The binding is process-free and owns no MQTT connection, Session, handle
registry, retry loop, or supervisor. `client_lifecycle_test.exs` supplies a
consumer-owned client process and exercises the public
`Wotex.Binding.MQTT.Client` port through both the adapter and real
`Wotex.Runtime.Subscription` children.

| Case | Executable result | Ownership conclusion |
|---|---|---|
| Retained read | The adapter supplies the configured finite timeout; the supplied client stops waiting at that bound; the binding returns `client_read_failed` | Network wait and temporary subscription cleanup remain client-owned |
| Invalid callback return | Every callback returns `invalid_client_return` with class `protocol` | Arbitrary client values never cross the binding boundary |
| Raise, throw, or exit | Every callback returns its stable `client_*_failed` code with class `unavailable` | Client exception values are not retained or exposed |
| Open failure | Runtime reports `transport_subscribe_failed`; no handle is entered in client state | The supplied client owns establishment and partial-resource cleanup |
| Close failure | Runtime reports `transport_unsubscribe_failed`; the failed handle remains in supplied-client state | The binding cannot claim remote release after a failed close |
| Concurrent owners | Each owner receives a distinct opaque handle; concurrent stops attempt each close exactly once | Handle cardinality and session resources live outside the binding |
| Session loss and restart | Runtime closes the old handle, the consumer supervisor starts a new owner, and the supplied client issues a fresh handle | Consumer restart policy owns resubscription |

The external client snapshot contains owner pids, opaque handles, and close
counts only. It contains no execution context or credential. Commands,
configuration inspection, and returned errors likewise exclude credential
material. Callback invocations may use the immediate execution context, but a
client implementation remains responsible for not retaining it.

## Recovery contract

`:reconnected` is valid only when the existing broker Session and subscription
survived. `:session_lost` and `:transport_down` stop the Runtime owner. With a
permanent child specification, the consumer supervisor creates a new owner and
the supplied client creates a new handle; the binding neither reconnects nor
reuses the old handle.

A failed unsubscribe is a failed attempt, not evidence of remote release. The
consumer client must reconcile that handle according to its broker Session and
connection policy. MQTT QoS handshakes, Session Expiry, Clean Start detection,
duplicate/loss ordering, and broker interoperability remain outside this
packet. WBM-C04 must exercise the exact archive through an independent consumer;
it does not convert these delegated responsibilities into binding guarantees.
