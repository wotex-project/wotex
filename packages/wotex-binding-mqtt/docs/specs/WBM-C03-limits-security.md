# WBM-C03: Limits and security boundary

Completion packet `WBM-C03`; package baseline `wotex_binding_mqtt 0.1.0`.
Requires `WBM-C01` and complements the WBM-C02 lifecycle proof.

## Exact admitted thresholds

`limits_security_test.exs` exercises each package threshold at the accepted
boundary and at one unit beyond it.

| Dimension | Accepted boundary | Rejected boundary | Stable outcome |
|---|---:|---:|---|
| Encoded or received JSON bytes | configured positive `max_payload_bytes` | `max_payload_bytes + 1` | `encoded_payload_too_large` or `received_payload_too_large` |
| Topic Name | 65,535 UTF-8 bytes | 65,536 bytes | `invalid_topic_name` |
| Topic Filter | 65,535 UTF-8 bytes | 65,536 bytes | `invalid_topic_filter` |
| Topic Filters per command | 256 | 257 | `too_many_topic_filters` before item 257 is validated or a client is called |
| JSON nesting depth | 64 | 65 | core cause `depth_limit_exceeded` |
| JSON nodes | 100,000 | 100,001 | core cause `node_limit_exceeded` |
| One JSON string | 262,144 bytes | 262,145 bytes | core cause `string_limit_exceeded` |
| One JSON collection | 10,000 members | 10,001 members | core cause `collection_limit_exceeded` |

The fixed 256-filter limit bounds validation and command construction work even
when the caller supplies a longer list. It is a package admission maximum, not
a broker capability claim; a supplied client may enforce a lower negotiated
packet, subscription, quota, or authorization limit.

## Delivery and receiver pressure

A real `Wotex.Runtime.Subscription` owner admits and decodes a sustained cohort
of 512 in-bound deliveries without introducing binding-owned state. A separate
case fills the consumer receiver mailbox to its configured
`max_queue_length` and proves the Runtime `overflow: :stop` policy reports
overload, stops the owner, and closes the exact supplied-client handle once.

This proves the configured message-count policy and cleanup path. It is not a
bound on BEAM heap size, scheduler delay, encoded input already allocated by a
caller, JSON codec working memory, client socket buffers, broker queues, or a
client connection process. Those budgets and any earlier payload rejection
remain consumer/client responsibilities.

## Credential and source authority

The execution context is intentionally passed to the consumer-supplied client
for the immediate callback. An executable adversarial port demonstrates that
such code can observe and retain the credential: the binding cannot sandbox a
client module selected by the consumer. Commands, transport configuration
inspection, results, and normalized nested client failures do not expose that
credential.

Likewise, `decode_frame/3` validates shape, Topic Filter matching, payload size,
and JSON only. The test can inject a syntactically valid delivery directly, so
acceptance cannot establish an authenticated broker, TLS peer, ACL decision, or
authorized Thing source. The consumer owns client trust, TLS and broker
identity, authentication, ACLs, credential lifetime, negotiated MQTT version,
and delivery provenance.

The package therefore makes a narrow redaction and admission claim, not a
whole-process memory, secret-erasure, authenticated-delivery, or broker
interoperability claim.
