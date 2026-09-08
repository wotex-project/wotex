# Executable evidence

Evidence collected 2026-09-08 using Elixir 1.20.2 / OTP 29.0.4.
Development contract supports Elixir 1.18+; the lower-version matrix has not been
executed in this workspace. Use CI before graduation. No consumer parity or
certification is inferred from unit coverage.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Interoperability

NOT RUN: a real ot-daemon/radio or POSIX RCP fixture was not supplied.
The default suite uses a local Unix peer to verify stream fragmentation, errors,
timeout and ownership; it is not Thread radio interoperability.
With an explicitly started OpenThread daemon:

```sh
WOTEX_PATH_DEPS=1 WOTEX_THREAD_DAEMON_SOCKET=/run/openthread-wpan0.sock \
mix test --include hardware test/interop/daemon_device_test.exs
```

This is read-only and must return a real version plus valid state. Dataset
installation, joining and commissioner/radio lifecycle are not yet implemented.

Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Evidence identities

The hashes identify reviewed test sources, not an immutable release or a promise
that all future test executions will pass. The mandatory gate and optional peer
commands above must be rerun after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/daemon_device_test.exs` | `624b89f9069b0ef5a12cc5af123fdc71ae6be12361b4ae6f2b25f1b9653346e9` |
| `test/wotex/thread/contract_test.exs` | `ce6378d3a63e0af4a842c480b2aedfff263f86bdd4e605f709c84dd835c9d638` |
| `test/wotex/thread/daemon_test.exs` | `1877bb41f4a31dfb5a702180d99e6b6e1f0eceeeb72f2615931b4f36556e06da` |
| `test/wotex/thread/dataset_test.exs` | `80c196b1756836b259e16fbe1ff8de58e4087fe462c033b4635820185bd76d73` |
| `test/wotex/thread/dependency_security_test.exs` | `827b01a3b81f234361673d8a7c9c4220b75fa06ad11915c7f89124e80fea1860` |
| `test/wotex/thread/mapping_test.exs` | `a00c7f0d76e63d98cd4289eb4500da805a8ddc9389e2160722f21594bf6d5b3a` |
| `test/wotex/thread/port_test.exs` | `6e92830343848cb643e529d63a331c739f3187d05d28a5f33a7d88c85bf47fbe` |
