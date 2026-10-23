---
id: lab-simulators
---

# Software device simulators

Run device behavior against WoTEx through real local transports. No physical
device or vendor account is required. Elixir owns test setup, inputs,
assertions and teardown. Container peers remain test dependencies and do not
enter the Lab package archive or production application.

| Peer | Owner and purpose |
| --- | --- |
| HTTP/SSE thermostat | Lab's `Reference.Thing` and HTTP fixture exercise Runtime reads and observations. |
| MQTT energy meter | Lab's MQTT fixture publishes device values through the disposable Mosquitto broker. |
| Modbus zone controller | Independent PyModbus 3.16.1 server; Elixir Testcontainers 2.4.0 owns each disposable device. |

## Zone controller

The device has four independent Modbus tables: coils, discrete inputs, holding
registers and input registers. Temperature is initially 21.5 °C, target
temperature 21.0 °C and measured power 420 W. Floating values use two
big-endian registers. The Elixir fixture supplies the complete initial register
image explicitly; the peer uses no wall clock or uncontrolled randomness.

Consumers use the public `Wotex.Modbus` API and
`Wotex.Runtime.ConsumedThing`, with a Thing Description, the package's draft Modbus profile
and an explicit local `nosec` credential port. The six integration tests cover:

- all four read functions and all four write functions;
- IEEE-754 temperature and power conversion through Runtime;
- Property writes and an explicit setpoint Action through the same consumed Thing;
- setpoint readback without treating an acknowledgement as a changed measurement;
- a real exception response followed by a successful exchange;
- isolation between two independent devices;
- peer shutdown and connection-owner cleanup.

This is a deterministic device/register peer. Thermal dynamics remain in
`Wotex.Lab.Simulators.Thermal`; its explicit model inputs and synthetic
observations are separate from protocol results.

From the repository root:

```sh
WOTEX_LAB_SIMULATORS=1 mix pkg wotex-lab test test/wotex/lab/modbus_simulator_test.exs
```

The explicit lane requires Docker. It builds the digest-pinned Python image
with a hash-verified PyModbus wheel, then starts fresh containers on dynamic
ports. Readiness requires the server's listening marker. Testcontainers stops
each peer after its test and provides its resource reaper for interrupted runs.
Normal `mix test` excludes `:simulator` and starts no Docker peer or reaper.

## Source and dependency choices

The peer uses the upstream
[PyModbus data model](https://pymodbus.readthedocs.io/en/v3.16.1/source/simulator/datamodel.html)
and TCP server, with a small Lab-owned launcher. PyModbus 3.16.1 is BSD-3-Clause;
its wheel identity is fixed in
[`requirements.txt`](https://github.com/wotex-project/wotex/blob/main/packages/wotex-lab/test/containers/modbus-simulator/requirements.txt).
The Python image digest and launcher live beside that file.
[Testcontainers](https://testcontainers.hexdocs.pm/Testcontainers.Container.html)
is an MIT-licensed test dependency. Its test profile selects patched Hackney
4.8.5 rather than the dependency's older HTTP-client requirement. Docker Unix
socket requests use direct connections; the fixture restores the previous pool
configuration after cleanup. No proprietary product simulator source is copied
into these fixtures.

The protocol packages retain their independent software peers: libmodbus for
Modbus, the BACnet stack for BACnet and the Rust peer for OPC UA. Their owning
package gates and software lanes remain authoritative; the Lab does not fork
their transports or convert one passing peer into a blanket protocol claim.
