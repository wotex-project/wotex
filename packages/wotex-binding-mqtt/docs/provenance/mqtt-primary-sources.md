# MQTT primary sources

Observed on 2026-09-02.

## MQTT 5.0

[MQTT Version 5.0, OASIS Standard, 07 March 2019](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
is the primary protocol source used for:

- MQTT Control Packet and Application Message terminology;
- QoS levels zero, one, and two;
- Topic Name and Topic Filter separation;
- the prohibition on wildcards in Topic Names;
- `+` as a complete single level and `#` as the final complete level;
- UTF-8, null-character, and 65,535-byte topic constraints;
- MQTT 5 shared Topic Filter syntax.

The package validates those transport-independent fields but does not implement
MQTT wire packets or a client session.

## MQTT 3.1.1

[MQTT Version 3.1.1, OASIS Standard, 29 October 2014](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html)
is retained as a primary compatibility source. Its Topic Name, Topic Filter,
wildcard, UTF-8 length, null-character, and three-level QoS rules align with the
common validations implemented here.

Shared subscriptions are an MQTT 5 extension. Whether a particular command can
use one is ultimately determined by the consumer-supplied client's negotiated
protocol version and broker capability.
