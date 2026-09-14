# Stable API candidate inventory

WBM-C06 freezes the reviewed `wotex_binding_mqtt` 0.1 API candidate. The
executable authority is `test/wotex/binding/mqtt/stable_api_test.exs` together
with `bin/check_stable_api.exs` in the ordinary `mix check --no-retry` gate.
This is a compatibility decision for the library contract, not a publication,
registry, certification, or wire-protocol conformance claim.

## Vector map

| Vector | Frozen assertion |
|---|---|
| WBM-S01 | The documented module/function surface and the four `Client` callbacks remain exact; default-argument convenience arities remain callable |
| WBM-S02 | The profile id, schemes, JSON media type, seven operations, and unsupported operation cells remain exact |
| WBM-S03 | Broker, Topic, QoS, Command, Delivery, JSON, and TransportConfig values retain their constructors, accessors, normalization, redacted inspection, bounds, and finite defaults |
| WBM-S04 | The seven WoT-operation rows retain their exact MQTT Control Packet, target term, QoS, retain, content type, and payload-limit behavior |
| WBM-S05 | Error `code`, `phase`, `class`, and documented detail keys remain matchable while messages may improve and foreign client terms remain redacted |
| WBM-S06 | Client callback tuple contracts and subscription-owner frame/status messages remain exact; session and supervision ownership stay with the consumer |
| WBM-S07 | Runtime publish/read/subscription outcomes retain their status and protocol metadata shapes, finite deadline rule, topic filtering, and failure normalization |
| WBM-S08 | Draft-sensitive terms cannot change merely because a newer editor draft appears; incompatible changes require an explicit version and migration record |

## Frozen callable surface

The following entries are the supported caller surface. Constructors with
defaults also expose their shorter arity: `Command.publish/4`,
`Command.subscribe/3`, `Command.unsubscribe/3`, and `TransportConfig.new/2`.
Generated struct and exception functions plus the hidden `Error.new/4,5`
constructor are implementation mechanics, not caller API.

| Module | Public functions or callbacks |
|---|---|
| `Wotex.Binding.MQTT` | `profile/0` |
| `Broker` | `new/1`, `href/1`, `scheme/1`, `host/1`, `port/1` |
| `Client` | callbacks `publish/3`, `read/4`, `subscribe/4`, `unsubscribe/4` |
| `Command` | `publish/5`, `subscribe/4`, `unsubscribe/4`, `broker/1`, `packet/1`, `operation/1`, `topic/1`, `filters/1`, `qos/1`, `retain?/1`, `payload/1`, `content_type/1`, `max_payload_bytes/1` |
| `Delivery` | `new/2`, `normalize/1`, `payload/1`, `topic/1`, `qos/1`, `retained?/1` |
| `Error` | exception fields `code`, `phase`, `class`, `message`, `details`; `class/1` |
| `JSON` | `encode/2`, `decode/2` |
| `Mapping` | `command/2`, `default_control_packet/1` |
| `QoS` | `normalize/1` |
| `Topic` | `validate_name/1`, `validate_filter/1`, `normalize_filters/1`, `matches?/2` |
| `Transport` | Runtime callbacks `request/3`, `subscribe/4`, `unsubscribe/4`, `decode_frame/3` |
| `TransportConfig` | `new/3`, `read_timeout/1`, `max_payload_bytes/1` |

## Values and defaults

The profile is `:mqtt`, admits only `mqtt` and `mqtts`, accepts
`application/json`, and contains exactly `readproperty`, `writeproperty`,
`observeproperty`, `unobserveproperty`, `invokeaction`, `subscribeevent`, and
`unsubscribeevent`. JSON content-type parameters and case normalize to
`application/json`.

QoS accepts integers or strings `0`, `1`, and `2`. Commands default to QoS 0
where the packet uses QoS, retain false, `application/json`, and a 1,048,576
byte payload limit. TransportConfig defaults to a 5,000 millisecond read timeout
and the same 1,048,576 byte limit. Topic strings admit at most 65,535 UTF-8
bytes; one command admits at most 256 Topic Filters. A consumer or broker may
enforce lower limits.

Broker inspection omits the original href, Command inspection omits the
payload, Delivery inspection omits the payload, and TransportConfig inspection
omits its opaque client configuration. These redaction choices are part of the
0.1 candidate.

## Draft-sensitive mapping

| WoT operation | Packet | Required target | Default retain |
|---|---|---|---|
| `readproperty` | `subscribe` | `mqv:filter` | must be explicitly `true` |
| `writeproperty` | `publish` | `mqv:topic` | `false` |
| `invokeaction` | `publish` | `mqv:topic` | `false` |
| `observeproperty` | `subscribe` | `mqv:filter` | `false` |
| `subscribeevent` | `subscribe` | `mqv:filter` | `false` |
| `unobserveproperty` | `unsubscribe` | `mqv:filter` | `false` |
| `unsubscribeevent` | `unsubscribe` | `mqv:filter` | `false` |

Only `mqv:controlPacket`, `mqv:topic`, `mqv:filter`, `mqv:qos`, and
`mqv:retain` have binding meaning. An explicit packet must equal the table,
publish Forms cannot carry a filter, subscribe/unsubscribe Forms cannot carry a
topic, and unprefixed lookalikes do not alter the mapping.

## Errors and Runtime results

Public failures preserve the tuple of `code`, `phase`, and `class`. The stable
code set is:

<!-- error-manifest:start -->

- broker: `invalid_broker_href`, `unsupported_broker_scheme`,
  `missing_broker_host`, `invalid_broker_port`,
  `broker_credentials_forbidden`, `broker_href_not_endpoint_only`;
- topic/value: `invalid_topic_name`, `topic_name_contains_wildcard`,
  `invalid_topic_filter`, `invalid_topic_filter_wildcard`,
  `invalid_shared_topic_filter`, `invalid_topic_filters`,
  `too_many_topic_filters`, `invalid_qos`, `invalid_delivery`, and
  `invalid_delivery_retain`;
- codec/command: `invalid_payload_limit`, `encoded_payload_too_large`,
  `received_payload_too_large`, `json_encode_failed`, `json_decode_failed`,
  `invalid_json_payload`, `invalid_command`, `invalid_retain`, and
  `unsupported_content_type`;
- mapping/configuration: `invalid_mapping_input`, `unsupported_operation`,
  `control_packet_mismatch`, `missing_mqtt_target`, `mixed_mqtt_targets`,
  `retained_read_required`, `invalid_transport_configuration`,
  `invalid_transport_options`, `invalid_client_port`, and
  `invalid_transport_option`;
- transport/client: `invalid_transport_input`, `invalid_subscription_packet`,
  `invalid_unsubscription_packet`, `unsupported_request_packet`,
  `deadline_exceeded`, `invalid_deadline_clock`, `client_publish_failed`,
  `client_read_failed`, `client_subscribe_failed`,
  `client_unsubscribe_failed`, `invalid_client_return`,
  `non_retained_property_read`, and `delivery_topic_mismatch`.

<!-- error-manifest:end -->

The `max_bytes` and `max_filters` detail keys remain stable for their limit
errors. Client failure details contain only `packet` and `operation`; arbitrary
return values, exceptions, credentials, payloads, and client configuration are
not copied. Human-readable messages may improve without a migration.

A successful publish is a Runtime `:accepted` result with `binding`,
`control_packet`, `qos`, and `retain` metadata. A retained read is `:ok` and
adds `topic`, `delivery_qos`, and `delivery_retained`. A subscription frame
decodes to payload plus `binding`, `control_packet`, `topic`, `qos`, `retained`,
`request_id`, and `operation` metadata.

## Client and migration boundary

The owner message forms remain `{:wotex_transport_frame, delivery}` and
`{:wotex_transport_status, status}`, where status is `:reconnected`,
`:session_lost`, or `:transport_down`. Client configuration and subscription
handles remain opaque and credential-free. The consumer owns connections,
sessions, supervision, TLS, authorization, reconnect, durability, and broker
capability negotiation.

Within the 0.1 line, a patch may improve prose, messages, and implementation
without changing the frozen observations above. Adding an operation, callback,
scheme, media type, accepted input, default, error tuple, or result/owner-message
shape requires explicit compatibility review. Removing or changing a frozen
observation is incompatible and requires a new version plus a migration record
that names the old behavior, replacement behavior, and consumer action. A newer
MQTT binding editor draft is evidence for review, never authority to silently
rewrite the dated mapping.
