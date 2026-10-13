# Dependency refresh

Reviewed: 2026-10-13. This record describes the selected source cohort;
historical archive and device evidence keeps its original inputs.

All eighteen package locks, the tooling lock and the three Lab host locks
were resolved to current compatible releases. Own published ExMaude is pinned
exactly to 0.5.0 in Lab and Workbench. Family packages retain their declared
Hex requirements and the explicit development path switch; unpublished
family archives are not represented as published releases.

The reviewed changelogs and upstream release notes require these decisions:

| Change | Adoption |
| --- | --- |
| Decimal 3.2.0 | Replace the vulnerable 3.1.1 cohort, update exact lock checks and test extreme rounding scales under bounded memory. Preserve the new precision-error behavior. |
| Mint 1.11, Finch 0.24 and HPAX 1.1 | Adopt HTTP allocation, framing and pool cleanup fixes without weakening caller deadlines or retry policy. |
| ExMaude 0.5.0 | Keep explicitly owned Port pools, finite deadlines and cancellation. Provision Maude separately; dependency installation is not interpreter or model qualification. |
| Req 0.7.5 | Adopt retry signing and redirect fixes. Existing explicit request policies remain the authority. |
| EMQTT 1.16.1, Gun 2.7 and Cowlib 2.21 | Require OTP 27 or later, already covered by the family lanes. WebSocket security limits retain their defaults; no widening through the new `ws_upgrade_options` option is needed. |
| Phoenix PubSub 2.4.1 | Reference hosts use ordinary subscriptions and broadcasts; no custom dispatcher migration is required. |
| Codepagex 0.2 and Zoi 0.18.11 | Retain explicit encoding/schema admission. The changed ASCII and coercion behavior does not add permissive fallback. |
| ExCheck 0.17 and documentation tooling | Adopt the compatible tooling cohort and new audits; optional absent tools remain classified separately. |
| Nerves Pi system 2.1.2 | Refresh the system closure and source checks. Renew firmware/device evidence independently. |

Primary EMQTT change comparison:
[1.16.0 to 1.16.1](https://github.com/emqx/emqtt/compare/1.16.0...1.16.1).
Gun/Cowlib's security release guidance is published by
[Nine Nines](https://ninenines.eu/articles/cowboy-2.20.0/).
The exact package archives and lock checks identify the remaining changelog
cohorts. No advisory suppression was added.

Executed validation includes thirteen full package gates (core, Conformance,
Continuum, Directory, Nx, Runtime, BACnet, HTTP, MQTT, BLE, CoAP, Matter and
Modbus), all three reference-host checks, and focused dependency/adapter tests
and Hex audits for the remaining packages. The broad OPC UA gate was stopped
when validation was narrowed to focused checks. Whole-family gates and
expensive native rebuilds belong to delivery milestones.

The observed hosted failures also require explicit test environment selection
for nested BACnet/Modbus software suites and a separate aggregate BLE harness
budget. Independent native-source advisories and the OPC UA peer Cargo lock
remain separate remediation inputs; the Hex refresh does not close them.
