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

Independent libcoap 4.3.5 at commit
`7cf7465b784baded4de183290c547d582becfd28`: PASS for UDP content, discovery-resource
read and unknown-resource status. This is a scoped one-shot CoAP proof, not a
DTLS/Observe/blockwise interoperability result.

```sh
docker build -t wotex-coap-peer test/interop/libcoap
docker run --rm -d --name wotex-coap-peer -p 127.0.0.1:56830:5683/udp wotex-coap-peer
WOTEX_PATH_DEPS=1 WOTEX_COAP_INTEROP_PORT=56830 mix test --include interop test/interop/libcoap_test.exs
docker stop wotex-coap-peer
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
| `test/interop/libcoap_test.exs` | `903bef8fb4368d78027b01293c1acdb3779eff9c8187e075defb97e580172888` |
| `test/wotex/coap/codec_test.exs` | `a810d7c2464a8e874009df3191a276ab72bbccf3ff81ae7ba600e646a5ba660d` |
| `test/wotex/coap/connection_test.exs` | `16ee05c3ab60ac7ffa7f4df7aacf500549c9c51b4c6f63a5f2db525e7f0d9259` |
| `test/wotex/coap/contract_test.exs` | `9d02da47a770f4d20aaa4ccac068b36709a948c004923e76904cdcbd6b31f888` |
| `test/wotex/coap/dependency_security_test.exs` | `651cb6942930d6f9e73db9299a701d8e68b93a3080746c9449eee707968c9bb8` |
| `test/wotex/coap/mapping_test.exs` | `464984b6e591be3d8d609f76a2953daf76a1f08f0d73bf3ca9741f1867142e8a` |
