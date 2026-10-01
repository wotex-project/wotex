# Wotex Zigbee package guidance

Wotex Zigbee (`packages/wotex-zigbee`, Hex `wotex_zigbee`) owns bounded TI ZNP
serial framing, one explicit coordinator owner, a finite ZDO/AF command set,
bounded peer-identified AF requests, typed ZDO descriptor responses and finite ZCL attribute values. It depends on
no sibling package. Repository rules are in the root `AGENTS.md`.

## Invariants

- Loading the package starts no process or serial I/O. A consumer supplies the
  `Wotex.Zigbee.SerialPort` adapter, exact hardware identity, expected firmware
  version, supervision policy, credentials, network custody and product policy.
- The first backend is TI CC26x2 SDK 2.30.00.34 ZNP with the bundled SWRA198
  Monitor/Test revision 1.14. Do not identify an arbitrary 802.15.4/Thread
  RCP or Silicon Labs EZSP device as this backend.
- One owner holds a serial port. It negotiates an exact `SYS_VERSION` before
  returning a handle. It admits one SREQ at a time and keeps a finite AREQ
  queue. A timeout or disconnect invalidates the epoch; never match an old
  uncorrelated SRSP to a new command.
- Network forming, resetting, permit-join, backup, restore, key changes and
  firmware updates have no implicit path through the finite command API.
- Synchronous admission, APS confirmation, ZCL response, report and physical
  effect are distinct observations. A 16-bit address is not durable identity.
- `usage-rules.md` ships in the Hex archive and describes the completed
  normative usage contract. The catalogue separately records implementation
  status. Keep consumer-specific notes under ignored `docs/tasks/local/`.

## Working on this package

Use `mix def Wotex.Zigbee [fun]` and `mix refs Wotex.Zigbee [fun]` before
changing a public API. Run focused tests, `mix check.fast --package
wotex-zigbee`, then `mix pkg wotex-zigbee check --no-retry` when ready. Run
`mix bench --package wotex-zigbee` for framing/codec performance changes only
when requested.
The full package gate includes docs, coverage, Dialyzer, archive and boundary
checks. There is no native build for this package.

Specifications and status live under `docs/packages/wotex-zigbee/specs/`.
The completion contract is
`docs/packages/wotex-zigbee/plans/wotex-zigbee-completion.md`.
