---
spec:
  id: WMB.14
  title: Release-candidate dossier
  status: accepted
  version: 1.0.0
  owner: wotex-modbus
  updated: 2026-09-14
---

# WMB.14 Release-candidate dossier

This dossier classifies the public `wotex_modbus` 0.1.0 candidate. It is a
verification map, not a release announcement, publication record, stable-API
promise or certification claim.

## Candidate identity and commands

`bin/check_archive.exs` builds exact Wotex core, Runtime and Modbus archives,
emits each archive SHA-256 plus the isolated consumer-lock SHA-256, and installs
the bytes through a temporary signed Hex registry. Archive digests are execution
outputs. Embedding a digest in a document contained by the same archive would be
self-referential, so a maintainer retains command output beside any later
immutable release record.

The developer command is:

```sh
WOTEX_PATH_DEPS=1 mise exec erlang@29.0.4 elixir@1.20.2-otp-29 -- \
  mix check --no-retry
```

It compiles with warnings as errors, checks formatting and runs the behavioral
test suite. Strict Credo, dependency audits, Dialyzer, Doctor, docs, coverage,
process-free loading and the archive consumer run as explicit release evidence.
The minimum archive and native-software lanes use Elixir 1.18.4/OTP 27.3.4.15;
current lanes use Elixir 1.20.2/OTP 29.0.4. The explicit software command is the
WMB.13 `mix wotex.software.run --workspace ABS` task. Release and publication
commands are not verification steps.

## Package and API review

The package application/name/version are `wotex_modbus`/`wotex_modbus`/`0.1.0`.
It requires Elixir `~> 1.18`, uses Mix, and declares Apache-2.0. The package is
pre-1.0 and its API remains unstable. Protocol, compatibility, Runtime and
archive-consumer tests exercise the documented public behavior. Public API
changes require deliberate compatibility review.

The supported surface consists of:

- `Wotex.Modbus` connection, request, eight-function, typed-float, health,
  compatibility and Runtime-profile entry points;
- Address, Command, Session and Error values;
- Codec, Value and Form Mapping functions;
- the explicit Connection process and Runtime Transport callbacks; and
- the uniquely named WMB.13 software build/run Mix tasks.

Expected protocol and admission failures return `%Wotex.Modbus.Error{}`. A
write acknowledgment is protocol evidence, not canonical Property truth. A
missing or malformed acknowledgment after transmission has unknown effect and
is not automatically retryable. Credentials, supervision, deployment policy,
application truth and authorization remain consumer-owned.

## Dependencies and toolchains

The archive metadata declares four runtime requirements:

| Dependency | Declared range | Candidate evidence |
| --- | --- | --- |
| `wotex` | `~> 0.1.0` | exact local 0.1.0 core candidate archive |
| `wotex_runtime` | `~> 0.1.0` | exact local 0.1.0 Runtime candidate archive |
| `jason` | `~> 1.4` | exact locked Hex 1.4.5 package |
| `telemetry` | `~> 1.3` | exact locked Hex 1.4.2 package |

The isolated consumer additionally locks core-owned `ex_json_schema` 0.11.5
and `decimal` 3.1.1. All seven entries must be Hex entries; the three candidate
archives must match the bytes built from their named source checkouts. The
consumer has independent Mix/Hex/dependency/build roots, no path dependency,
and loads package BEAMs only from its own build. This proves the exact candidate
graph, not every solver result allowed by the declared ranges.

## Standards and profile boundary

The implemented protocol scope is the classic Modbus TCP subset in Modbus
Application Protocol 1.1b3 and Modbus Messaging on TCP/IP Implementation Guide
1.0b: functions 1, 2, 3, 4, 5, 6, 15 and 16. Wotex Form mapping implements the
numeric TCP subset pinned to the W3C WoT Modbus binding draft revision
`ea0ec98f864feca914e175026c441c3c36e8b1a9` dated 2026-08-26, with Thing
Description 1.1 Form and operation vocabulary used through core and Runtime.
This is not W3C conformance, endorsement or certification.

WMB-C05 subscription machinery is inapplicable because the only admitted
profile declares no subscription operations; the public compatibility methods
return the deliberate unsupported result. WMB-C07 native-runtime framing is
inapplicable because production protocol execution is BEAM TCP. The C peer and
native command guardian are test orchestration governed by WMB.13, not an
alternate production backend.

## Archive, legal and security review

The package contains the public source, README, LICENSE, exact Modbus NOTICE,
SECURITY, governance/contribution documents, specifications, fixtures and
provenance. It excludes repository control instructions, agent configuration,
tests, build output, dependencies, coverage/docs output, PLTs, credentials,
sockets, downloaded native sources and executable verification scripts. The
archive checker rejects symlinks and embedded source-checkout paths.

The package defines no Application callback and starts no transport while being
loaded. Classic Modbus TCP supplies no confidentiality, integrity or peer
authentication. Modbus Security, generic TLS, RTU/serial and deployment network
policy are not silently inferred from a URI or connection option.

## Executed evidence and nonclaims

The source-bound cohorts and exact result classifications live in
`docs/provenance/executable-evidence.md`. Candidate archive, minimum/current
toolchain and native-peer outputs are retained outside the repository and remain
bound to the source identity printed by each run. Checked-in generated receipts
do not silently advance when implementation or verification sources change.

This packet does not prove public Hex availability, publication, artifact
authenticity, third-party adoption, physical hardware behavior, serial RTU,
Modbus Security, a stable API, certified protocol/W3C conformance, authorization,
canonical device state, exactly-once mutation or consumer migration.
