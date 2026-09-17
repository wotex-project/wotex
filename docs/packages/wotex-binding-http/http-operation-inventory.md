# HTTP operation and vector inventory

This inventory is the `WBH-C01` evidence map for package baseline
`wotex_binding_http 0.1.0`. It binds every declared Runtime operation, plus the
single unsupported Thing-level aggregate cell, to implementation source,
observable outcome, named positive and negative vectors, and a revision-pinned
authority. The vectors execute in
`test/wotex/binding/http/operation_inventory_test.exs` and assert that rejected
inputs reach neither request nor subscribe client callbacks.

| Cell | Runtime operation | Implementation path | Package outcome | Positive vector | Negative vector | Authority |
| --- | --- | --- | --- | --- | --- | --- |
| WBH-OP01 | `readproperty` | `HTTP.profile/0` → `Form.build/2` → `Transport.request/3` | GET request | WBH-V01-P | WBH-V01-N | TD11-8.3.1-T32 |
| WBH-OP02 | `writeproperty` | `HTTP.profile/0` → `Form.build/2` → `Transport.request/3` | PUT request | WBH-V02-P | WBH-V02-N | TD11-8.3.1-T32 |
| WBH-OP03 | `invokeaction` | `HTTP.profile/0` → `Form.build/2` → `Transport.request/3` | POST request | WBH-V03-P | WBH-V03-N | TD11-8.3.1-T32 |
| WBH-OP04 | `queryaction` | `HTTP.profile/0` → `Form.build/2` → `Transport.request/3` | GET ActionStatus request | WBH-V04-P | WBH-V04-N | PROFILE-WD-6.2.2.2 |
| WBH-OP05 | `cancelaction` | `HTTP.profile/0` → `Form.build/2` → `Transport.request/3` | DELETE ActionStatus request | WBH-V05-P | WBH-V05-N | PROFILE-WD-6.2.2.3 |
| WBH-OP06 | `observeproperty` | `HTTP.profile/0` → `Form.build/2` → `Transport.subscribe/4` | GET SSE open | WBH-V06-P | WBH-V06-N | PROFILE-WD-7.2.1.1 |
| WBH-OP07 | `unobserveproperty` | `HTTP.profile/0` → `Transport.unsubscribe/4` | close; no HTTP exchange | WBH-V07-P | WBH-V07-N | PROFILE-WD-7.2.1.2 |
| WBH-OP08 | `subscribeevent` | `HTTP.profile/0` → `Form.build/2` → `Transport.subscribe/4` | GET SSE open | WBH-V08-P | WBH-V08-N | PROFILE-WD-7.2.2.1 |
| WBH-OP09 | `unsubscribeevent` | `HTTP.profile/0` → `Transport.unsubscribe/4` | close; no HTTP exchange | WBH-V09-P | WBH-V09-N | PROFILE-WD-7.2.2.2 |
| WBH-OP10 | `thing_operations/0` | `HTTP.profile/0` and defensive `Form.build/2` | unsupported aggregate cell | WBH-V10-P | WBH-V10-N | WRT-THING+WBH.01 |

## Authority keys

- `TD11-8.3.1-T32` is [WoT Thing Description 1.1, Recommendation
  2023-12-05, section 8.3.1, Table 32](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/#protocol-bindings),
  which defines missing-`htv:methodName` defaults of `GET`, `PUT`, and `POST`
  for `readproperty`, `writeproperty`, and `invokeaction`, respectively.
- `PROFILE-WD-6.2.2.2` and `PROFILE-WD-6.2.2.3` are the [WoT Profiles Working
  Draft 2025-11-04 action-status sections](https://www.w3.org/TR/2025/WD-wot-profile-20251104/#actions),
  which map `queryaction` to `GET` and `cancelaction` to `DELETE`. Treating
  those methods as package defaults is a versioned package choice, not a TD
  1.1 default.
- `PROFILE-WD-7.2.1.1`, `PROFILE-WD-7.2.1.2`, `PROFILE-WD-7.2.2.1`, and
  `PROFILE-WD-7.2.2.2` are the [same draft's HTTP SSE operation
  sections](https://www.w3.org/TR/2025/WD-wot-profile-20251104/#http-sse-profile),
  which specify `GET` opens and connection termination for the paired stop
  operations. The consumer-supplied client owns the connection.
- `WRT-THING+WBH.01` is the pinned Runtime `thing_operations/0` set plus the
  `WBH.01` explicit unsupported-cell contract. TD 1.1 Table 32 defines some
  aggregate HTTP defaults, but this package deliberately declares none of the
  Runtime Thing-level operations and must not silently apply those defaults.

These authorities fix method and close mappings only. They do not establish
complete HTTP Basic/SSE Profile conformance, Binding Registry membership,
independent interoperability, network-client correctness, or remote effect.
