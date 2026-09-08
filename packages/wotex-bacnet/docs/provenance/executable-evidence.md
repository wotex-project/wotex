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
The reviewed Decimal advisory metadata exception and regression are documented
in SECURITY.md and the dependency-security test.

## Interoperability

Independent BACnet C stack at commit
`3603048350b8ba543ec76cf6aa8a232b3f4d442d`: PASS for Analog Output 1 Present_Value,
write/readback/restore and unknown-object Error. The test owns its complete
BACstack group with retries disabled and exercises actual UDP transport.
No COV, routed network, MS/TP or BACnet/SC claim follows.

```sh
docker build -t wotex-bacnet-peer test/interop/cstack
docker run --rm -d --name wotex-bacnet-peer -p 127.0.0.1:57808:47808/udp wotex-bacnet-peer
WOTEX_PATH_DEPS=1 WOTEX_BACNET_INTEROP_PORT=57808 mix test --include interop test/interop/cstack_test.exs
docker stop wotex-bacnet-peer
```

Container source commits are pinned. Base-image/package-manager inputs may move;
these are reproducible source fixtures, not claims of bit-identical image builds.
Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Evidence identities

The hashes identify reviewed test sources, not an immutable release or a promise
that all future test executions will pass. The mandatory gate and optional peer
commands above must be rerun after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/cstack_test.exs` | `c489e4c14cd192ea8b221706d24a239a90c51a6f52be8da173c719b4190bf0c3` |
| `test/wotex/bacnet/bacstack_test.exs` | `5676b9f6138d6f2d7e605f6adfff56b35f9b80de9f66b5caa03b1fd3af934dae` |
| `test/wotex/bacnet/ipv4_test.exs` | `6a6c65520ec545d6951f89b8494bea416e9b98003cc550f064c15ceb5afc97b2` |
| `test/wotex/bacnet/mapping_test.exs` | `9ea0ab4a1e054ac8614ed3505495e0d0b70a4f0f2b038ece33df5d0fe5d53e36` |
| `test/wotex/bacnet/port_test.exs` | `52b2ed99b2edac4d86d6f0bf9ee49d61d45df4ff2a049daef3202d8e35f51ada` |
| `test/wotex/bacnet/value_test.exs` | `c6c4c274341713cf7d3753c00f5b876e0039b124198ca33e84688dba416d94d9` |
