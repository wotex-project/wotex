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
| `test/wotex/bacnet/bacstack_test.exs` | `7a1c1bcf7cb5b11136c0d07c1cf73f1636cd4e913280e4e79780fc7a11b7d18c` |
| `test/wotex/bacnet/contract_test.exs` | `42a76e6098281c95fb659039b0c1e64f35d9d9ee0486765461c828f85ffa4193` |
| `test/wotex/bacnet/dependency_security_test.exs` | `d99c1cbc0641ea67f70eb3d9ceeec62d6ab4619b9547d6f96455ff4d1dac199c` |
| `test/wotex/bacnet/ipv4_test.exs` | `34327571fe0863b932ab3d9fb14e23d0c34dd75a9fca0ab415a25cdd517fe88a` |
| `test/wotex/bacnet/mapping_test.exs` | `9ea0ab4a1e054ac8614ed3505495e0d0b70a4f0f2b038ece33df5d0fe5d53e36` |
| `test/wotex/bacnet/port_test.exs` | `52b2ed99b2edac4d86d6f0bf9ee49d61d45df4ff2a049daef3202d8e35f51ada` |
| `test/wotex/bacnet/value_test.exs` | `c6c4c274341713cf7d3753c00f5b876e0039b124198ca33e84688dba416d94d9` |
