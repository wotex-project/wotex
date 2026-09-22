# CoAP/DTLS/OSCORE physical lab

Protocol contract: `wotex-coap`.

Runbook status: planned. This does not change source implementation status.

## Hardware class

Select a programmable constrained node with an open CoAP stack or a finished
CoAP device that requires no vendor SaaS.

## Acceptance

- GET, PUT and POST interaction mapping;
- Observe lifecycle;
- confirmable retransmission under packet loss;
- duplicate-message handling;
- blockwise transfer where owned by the package;
- explicitly selected DTLS or OSCORE profile;
- credential and key material outside Thing Descriptions;
- peer reboot and sequence or replay behaviour.

Do not purchase hardware until the accepted package specification identifies
the physical operations that remain unproven.
