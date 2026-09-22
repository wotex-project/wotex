# OPC UA physical lab

Protocol contract: `wotex-opcua`.

Runbook status: planned. This does not change source implementation status.

## Hardware class

Use an independent industrial gateway, PLC or appliance that exposes a
standards-based OPC UA server without mandatory cloud services.

## Acceptance

- secure session establishment;
- browse;
- read and write;
- subscription;
- reconnect and session renewal;
- namespace and node-identity stability;
- server restart;
- bad status codes mapped without invented values;
- certificate and credential custody outside Thing Descriptions.
