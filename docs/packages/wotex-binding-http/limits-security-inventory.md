# Limits and security boundary evidence inventory

This `WBH-C03` inventory binds every package-owned limit and security cell to a
named executable vector for package baseline `wotex_binding_http 0.1.0`.
Admission checks are local checks on already supplied Elixir values. They do
not turn this binding into an HTTP client, an authorization service, or a hard
whole-process memory boundary.

| Cell | Reviewed contract | Named vectors |
| --- | --- | --- |
| WBH-S01 | Exact configuration defaults and positive validation for request, response, event, field-count, field-byte, and URI-byte limits | WBH-S01-P, WBH-S01-N |
| WBH-S02 | Encoded request body is admitted exactly at the configured byte threshold and rejected one byte above before client I/O | WBH-S02-P, WBH-S02-N |
| WBH-S03 | Complete response body is admitted exactly at the configured byte threshold and rejected one byte above before JSON decoding | WBH-S03-P, WBH-S03-N |
| WBH-S04 | Framed event data is admitted exactly at the configured byte threshold and rejected one byte above before JSON decoding | WBH-S04-P, WBH-S04-N |
| WBH-S05 | Complete request and response field lists are admitted at the configured count and rejected at one over | WBH-S05-P, WBH-S05-N |
| WBH-S06 | Complete request and response field lists are admitted at the configured aggregate name/value byte threshold and rejected at one over | WBH-S06-P, WBH-S06-N |
| WBH-S07 | Final request targets are admitted at the configured URI-byte threshold and rejected at one over | WBH-S07-P, WBH-S07-N |
| WBH-S08 | Native JSON input is structurally validated with the configured string/key-payload ceiling before encoded output materialization; encoded syntax overhead receives a second exact byte check | WBH-S08-P, WBH-S08-N |
| WBH-S09 | Absolute integer, UTC, and absent deadlines cross the port unchanged; only a supplied-client `:timeout` result establishes enforcement for binding classification | WBH-S09-P, WBH-S09-N |
| WBH-S10 | A returned redirect is never followed by the binding; actual Action-status targets and credentials remain separate callback arguments for client destination/audience admission | WBH-S10-P, WBH-S10-N |
| WBH-S11 | Nested external error, exception, exit, and throw terms from every client callback are replaced by credential-free binding errors | WBH-S11-N |
| WBH-S12 | Sustained valid frames respect Runtime's configured receiver-mailbox drop boundary and do not create a package-owned queue | WBH-S12-P |
| WBH-S13 | A nested client connection-process exit reason is reduced by Runtime to lifecycle status and never copied into a binding value or receiver delivery | WBH-S13-P |

The vector names appear in `limits_security_test.exs` and
`integration_test.exs` under `test/wotex/binding/http/`.

## Exact package defaults and measurements

The package defaults are 1,048,576 request bytes, 4,194,304 response bytes,
1,048,576 event bytes, 64 fields, 65,536 aggregate field bytes, and 8,192 URI
bytes. Body, event, and URI limits use `byte_size/1`. Aggregate field bytes are
the sum of every normalized field name and field value. They deliberately do
not claim a bound for client-owned HTTP framing, compression, decompression, or
transport-library data structures.

The binding passes response/event, field, and URI ceilings on the immutable
request so a supplied client can stop incremental input before constructing a
complete response or event. Local response/event checks are defense in depth
after a client has already returned a complete value. Likewise, caller-owned
native request terms exist before this package sees them. Core JSON validation
rejects excessive nesting, nodes, collection members, single strings, and
aggregate string/key payload before it builds encoded output; JSON punctuation
and escaping can still make the bounded intermediate output larger than
`max_request_bytes`, so the package repeats the exact encoded-byte check.
Neither stage is a hard total-heap guarantee.

## Client and consumer security obligations

The binding validates URI syntax, length, forbidden credential fields, and
returned values. It neither resolves DNS nor opens a connection. The supplied
client and consumer host must authorize the final `Request.uri/1`, every DNS/IP
result, proxy route, and every redirect hop before I/O. They must apply a
credential only when that exact target remains inside the credential's
audience; automatic redirect forwarding is not authorized by a syntactically
valid `Location`. This is especially important for absolute Action-status
targets, which may differ from the selected Form authority. WBH-S10 proves the
separate port values and the binding's no-follow behavior, not an arbitrary
client's policy.

The supplied client also reads the clock matching `Request.deadline/1`, derives
the remaining budget with `Wotex.Runtime.Context.remaining_ms/2`, cancels wire
work on expiry, and reports `{:error, :timeout}`. WBH-S09 proves propagation and
classification; it cannot prove that an arbitrary client honored the clock.

Runtime can bound a receiver mailbox through `max_queue_length` and an overflow
policy. The supplied streaming client must separately bound its socket/parser
state and pace or stop sends to the Runtime owner. Sequential sustained-load
evidence cannot prove a hard bound against hostile concurrent senders or bound
the client's connection-process mailbox, scheduler queues, total heap, durable
delivery, reconnection, or event loss.
