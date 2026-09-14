# Executable evidence

Current implementation: concrete and wildcard read paths, bounded TLV, the P01
descriptor/report/batch-result value layer, explicit Client contract and the
one-shot Python factory adapter. P01 executes WMA-F01–F06, WMA-F10 and WMA-F12
through public Elixir operations. Its reusable C++17 descriptor/value unit passes
normal and sanitizer builds on the required Linux x86_64 compiler, CMake and
Ninja versions. P02 implements the SDK storage delegate, exclusive versioned
store and operational-key/certificate-store binding. Python SDK-contract tests
use an explicit test controller.

No first-party persistent C++ controller, generated durable authority, actual
commissioning/CASE/attestation, native Interaction Model call or subscription
lane is accepted. The remaining P03–P09 controller/software-peer packages are
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

## P02 durable storage evidence

`elixir bin/check_p02_native.exs` runs outside the developer gate in the same
pinned Debian 12/Linux x86_64 environment. It verifies the connectedhomeip
`250a9e6c50ee2068107f3c4808b680f5f2925415` archive, the exact nlassert/nlio
gitlink archives and nlohmann/json 3.11.3 before compilation. The production
storage class derives from the pinned `chip::PersistentStorageDelegate`; the SDK
binding compiles calls to `PersistentStorageOperationalKeystore::Init` and
`PersistentStorageOpCertStore::Init` with that delegate.

`test/native/storage_test.cpp` passes normal and ASan/UBSan builds. It observes
create/open authority combinations, exact fabric/controller/vendor identity,
exclusive locking, 0700/0600 permissions, opaque empty/binary/65535-byte values,
SDK short-buffer semantics, durable restart and delete behavior, malformed,
duplicate, noncanonical Base64, extra-field, 4096-key, 16 MiB and symlink
boundaries. Forked children terminate at every temporary-write, fsync, intent,
rename and directory-fsync checkpoint. An incomplete commit cannot reopen stale
state; state past the durable rename boundary retains the written value. A
commit failure poisons the live owner. The lane starts no SDK controller and
does not generate or validate cryptographic credentials.

`elixir bin/check_p02_advisories.exs` separately submits OSV GIT queries for the
exact connectedhomeip, nlohmann/json, nlassert and nlio revisions. The recorded
P02 run returned no advisories for those four revisions. This is a live advisory
result at execution time, not a guarantee about future disclosures or unqueried
transitive sources; there are no P02 native advisory waivers.

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
| `native/CMakeLists.txt` | `59b2f9a94f77328ac50cf0f3609173ab9ec539e58c3211d150437288c8477cc6` |
| `native/include/wotex_matter/storage.hpp` | `9fb513934405794269c2fdbe45aa3709b76613b771974fd2fe304c17681ef7b4` |
| `native/include/wotex_matter/sdk_storage.hpp` | `27b14aed84317a580e53eef46c0e8ae82d5ec6c6a31e9ff314b26f9ae62521ea` |
| `native/src/storage.cpp` | `882ac467cb4fc3b079afe82d630c8efa6a506c541eccbbdcdcb90c35c9c2487b` |
| `native/src/sdk_storage.cpp` | `79b8f29f1084e747f4ae6d858a2b385d2694dafb846e0e9ba96be53ffff507fb` |
| `test/native/storage_test.cpp` | `129d3d8b7019bbe5a4f84bf764de6acdf52f264d1e0cb38dba165774e12fad92` |
| `bin/check_p02_native.exs` | `6db00bb2b78becdc323ed1d0974fb9f321362c423c01b88033f5c227ec338c2b` |
| `bin/check_p02_advisories.exs` | `4fb2991fa0daff53c92cd14ca8f2c58e518ec974f30f123575834b1a2e38f7e2` |
| `test/bridge/matter_bridge_test.py` | `f2f41e95a68180c117433d395221d4984683e333edddad2f325cdb49fd52422b` |
| `test/wotex/matter/contract_test.exs` | `45d55f0df387085d6ed9f7667cc41267ce63e0c0e084578dbcb1b0150e8f8099` |
| `test/wotex/matter/path_value_test.exs` | `d71f4b218f6bea4e2d3b2c87958646ff6fd928c4cf8af111fffad21351bde6ed` |
| `test/wotex/matter/sdk_test.exs` | `603e0dd15e2a31de7d226704632a5786acb7b2e60b19d66e4ca77c761fb96301` |
| `test/wotex/matter/tlv_test.exs` | `eb245cee8ec6ae71543839d00b5faf2468c66a496c7e06695772a5dcab3fd242` |
