# Executable evidence

Evidence collected 2026-09-08 using Elixir 1.20.2 / OTP 29.0.4.
That historical baseline covered the stated toolchain only. The package
requires fresh source-specific matrix and archive checks before graduation. No consumer parity or
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

Real secure asyncua 2.0.1 peer: PASS for read, write/readback/restore, browse,
unknown-node failure, expired certificate, wrong host/URI, untrusted CA and
revoked certificate. Both sides use asyncua; this is a real wire/security proof,
not independent-stack interoperability or OPC Foundation certification.
Intermediate trust chains are outside the implemented security profile.

```sh
python3 -m venv /tmp/wotex-ua-test
/tmp/wotex-ua-test/bin/pip install -r priv/requirements.txt
/tmp/wotex-ua-test/bin/python test/interop/secure_peer.py /tmp/wotex-ua-fixture
# In a second terminal, after config.json exists:
WOTEX_PATH_DEPS=1 WOTEX_OPCUA_INTEROP_CONFIG=/tmp/wotex-ua-fixture/config.json mix test --include interop test/interop/asyncua_test.exs
```

Stop the explicitly started peer afterward. The fixture generates disposable
keys/certificates outside the repository; do not use them as operational trust.
The Python requirements are fully version-pinned. The Elixir gate does not
install Python dependencies; audit the optional environment separately with
`pip-audit --disable-pip --no-deps -r priv/requirements.txt`.

Interoperability tags are excluded by default. Explicit invocation requires the
configured peer and must fail if that peer or expected response is missing.

## Evidence identities

The hashes identify reviewed test sources, not an immutable release or a promise
that all future test executions will pass. The mandatory gate and optional peer
commands above must be rerun after relevant changes.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/asyncua_test.exs` | `d1eb6dae68bc989ccb5b1df7778d80c9512781cdcc2fb248d4c43b1a09567740` |
| `test/wotex/opcua/asyncua_test.exs` | `d36277d2fd7ec90e6fb393f19ee6730c600e6e83713190e83146dfce67182e6e` |
| `test/wotex/opcua/binary_test.exs` | `bf2417a5fa093a59adaaf262ca08f614bbc995366961bead7df60b9de45c6a96` |
| `test/wotex/opcua/contract_test.exs` | `e9d677fe79d5d8b4fdb88d1d597b0d6bb3cb2bdbe2889a9cc4003432cb5e5f33` |
| `test/wotex/opcua/dependency_security_test.exs` | `3c45b778a241b2a577f9481c6a7ec08f4f8ec747f72a6d5e7deaf3265510e072` |
| `test/wotex/opcua/mapping_test.exs` | `2768c115820bcd56364bde5d2101bc13dc242fc92f5ca0a2c1b62b01e7812f93` |
| `test/wotex/opcua/port_test.exs` | `bf7dfcf70fa9afc680f07d4b861c56ecf954b01e8d280b12d7981849cc19cb48` |
| `test/wotex/opcua/value_test.exs` | `5c173dfdd5a27d60887064fe64041a3d5fd2434442bcd8abe431e00345f96089` |
