# Executable evidence

Current implementation: concrete and wildcard read paths, bounded TLV, the P01
descriptor/report/batch-result value layer, explicit Client contract and the
one-shot Python factory adapter. P01 executes WMA-F01–F06, WMA-F10 and WMA-F12
through public Elixir operations. Its reusable C++17 descriptor/value unit passes
normal and sanitizer builds on the required Linux x86_64 compiler, CMake and
Ninja versions. Python SDK-contract tests use an explicit test controller.

No first-party persistent C++ controller, durable authority, actual
commissioning/CASE/attestation, native Interaction Model call or subscription
lane is accepted. The remaining P02–P09 controller/software-peer packages are
implementation work. An arbitrary supplied factory is not a substitute for that
acceptance.

## Developer gate

`WOTEX_PATH_DEPS=1 mix check --no-retry` runs warnings-as-errors compilation,
formatting and the behavioral test suite. Runtime path dependencies require the
explicit switch; the archive preserves ordinary Hex dependency declarations.
Strict Credo, dependency audits, Dialyzer, Doctor, ExDoc, coverage, packaging,
out-of-tree compilation, Application-free loading and native builds are explicit
release or packet evidence. The pinned Decimal parser regression remains active;
there are no advisory waivers. See SECURITY.md and the dependency-security test.

## P01 native value evidence

`elixir bin/check_p01_native.exs` runs outside the developer gate. It uses the
content-pinned `node:24-bookworm` container as a Debian 12 environment, selects
Linux x86_64, and requires G++ 12.2.0, CMake 3.25.1 and Ninja 1.11.1. It compiles
`native/src/value.cpp` with C++17 and warnings as errors, then runs
`test/native/value_test.cpp` in normal and AddressSanitizer/UndefinedBehaviorSanitizer
builds. Both variants pass. This proves the P01 pure descriptor and conversion
unit; it does not prove SDK linkage, IPC, controller ownership or interoperability.

## Acceptance boundary

[WMA.13](../specs/WMA.13-native-backend.md) defines the required native binary,
Mix/ExUnit tasks, exact version lanes and credit/resource tests. Its corpus is
specified and unexecuted. A passing current gate, a listed test path or a source
hash cannot establish execution of that target. Each completed software run must
bind case, corpus, source, SDK/binary, toolchain and cleanup-result hashes.
The mandatory runtime matrix is Elixir 1.18.4/OTP 27.3.4.15 and Elixir
1.20.2/OTP 29.0.4. Only identified executed lanes count as passing evidence.

## Committed source identities

These hashes identify the committed implementation/test inputs reviewed here;
they are not release artifacts or a claim about every future run. Fixture WIP is
excluded. Native software results require their own immutable manifest.

| Source | SHA-256 |
| --- | --- |
| `docs/specs/fixtures/contract-v1.json` | `207561f8438f8037152d62d80f6b2237b1e745fcf6f54ffa18d4dc742e41ddc8` |
| `lib/wotex/matter/address.ex` | `a6dc08d86ce6b04f801009712db54edbbb6fe907a15a90765d11676f7c6e91ec` |
| `lib/wotex/matter/descriptor.ex` | `b0aff7d2bcdffbf7544ce63ac7a58a5d359badd6fd4618d1f21d48485cd73e77` |
| `lib/wotex/matter/endpoint_catalogue.ex` | `f3587bb26dfa64776891ba7b2f9ef8daa8156096aa0225551da8763af578b498` |
| `lib/wotex/matter/path_results.ex` | `6f6e3f34a71650f0af5f27072f3208961e7198d47bbbabc73125dc4854600eee` |
| `lib/wotex/matter/tlv.ex` | `41ae9116b5e64f5f3e5999ae509b9c8b44540d536d0efa46d739d2d032b035c8` |
| `native/include/wotex_matter/value.hpp` | `c663ebdcd4e2be5c29a5419c23b0fd5410f5830681930767360cb5628aae0422` |
| `native/src/value.cpp` | `1f93591c9c55a18e724228cb39290b36ef421ecb6c43e91db9241ef159207455` |
| `test/native/value_test.cpp` | `82a92edc4c4c38fd34627fa8abed12195691482e9b330dd31bffd878f130c4dd` |
| `test/bridge/matter_bridge_test.py` | `f2f41e95a68180c117433d395221d4984683e333edddad2f325cdb49fd52422b` |
| `test/wotex/matter/contract_test.exs` | `45d55f0df387085d6ed9f7667cc41267ce63e0c0e084578dbcb1b0150e8f8099` |
| `test/wotex/matter/path_value_test.exs` | `d71f4b218f6bea4e2d3b2c87958646ff6fd928c4cf8af111fffad21351bde6ed` |
| `test/wotex/matter/sdk_test.exs` | `603e0dd15e2a31de7d226704632a5786acb7b2e60b19d66e4ca77c761fb96301` |
| `test/wotex/matter/tlv_test.exs` | `eb245cee8ec6ae71543839d00b5faf2468c66a496c7e06695772a5dcab3fd242` |
