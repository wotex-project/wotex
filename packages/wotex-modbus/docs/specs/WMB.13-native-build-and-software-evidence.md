---
spec:
  id: WMB.13
  title: "Native peer build and software evidence"
  status: accepted
  version: 1.1.0
  owner: wotex-modbus
  updated: 2026-09-09
---

# WMB.13 Native peer build and software evidence

The runtime is the existing BEAM TCP client. The independent peer is the C
libmodbus server in `test/interop/libmodbus/server.c`. Neither a Python runtime,
a C client wrapper nor a native runtime helper belongs to this profile.
Build and test orchestration belongs to Mix and ExUnit. These task contracts
are planned; the shell/Python harness has separate executed evidence in
[provenance](../provenance/executable-evidence.md).

## WMB-N01 — Explicit build task

`mix wotex.software.build --workspace ABS` requires one absolute workspace and
rejects duplicate, unknown or positional arguments. It uses an empty disposable
directory or verifies an existing matching manifest. It rejects symlink roots,
unrelated contents and changed inputs. No native SDK compilation, download or peer process
starts during dependency loading, `mix compile` or normal `mix test`.
The first-party command guardian is compiled explicitly by task builds and its
isolated native unit tests, using a POSIX C11 compiler. The source contract in
`test/interop/native/README.md` defines owner EOF, bounded output and
process-group cleanup; it does not claim adversarial descendant
containment. The compiler identity belongs in the helper build manifest.

The source is libmodbus 3.1.12 at commit
`9af6c16074df566551bca0a7c37443e48f216289`, archive SHA-256
`5d0f56cdd9f4f4bc6863dcac6bc9bdc7ea862566aefa29eef2f1bf649cc1ea3a` from
`https://codeload.github.com/stephane/libmodbus/tar.gz/9af6c16074df566551bca0a7c37443e48f216289`.
The checked-in Dockerfile fixes the Linux base image and native build flags.
The task drives that build using separate executable/argument values, never
shell interpolation. Archive extraction rejects traversal and escaping links.
Downloads have a 30-second deadline and 8 MiB bound; build time is bounded to
10 minutes. Failure is nonzero and never creates a ready manifest.

`peer-manifest.json` uses schema `wotex.modbus.native-peer@1`, exact source URL,
commit/archive hash, fixture source hashes, image digest, OS/architecture,
compiler/version, configure/compiler/linker options, binary/library hashes and
sanitizer configuration. A ready manifest is atomically written only after
verification. Reuse verifies every recorded input and artifact hash.
The task neither changes Git state nor installs a system-wide library.

## WMB-N02 — Owned software run

`mix wotex.software.run --workspace ABS` accepts the same argument contract and
requires a verified ready manifest. It starts only its recorded C peer in a
disposable container with a loopback-only ephemeral port. Readiness requires
the peer's bounded explicit ready event within 15 seconds. The task owns the
container identity, test process, captured output and result directory.

The task invokes a separate Mix test process with
`--include interop --include software --exclude hardware --seed 731942` and
`WOTEX_REQUIRE_SOFTWARE=1`. It supplies only its own endpoint and result path.
Missing Docker, peer, response or test configuration is failure, never a skip.
The suite retains the eight-function/readback/exception assertions, standalone
and Runtime corpora, 1,000 sequential operations, 100 open/close cycles,
32 concurrent callers and repeated timeout/close/malformed-peer failures.

An ExUnit-owned Port or monitored OS process provides finite cancellation;
unbounded `System.cmd/3` is insufficient. Test execution has a 180-second
deadline. All exits, exceptions and termination signals stop the exact test
process and peer; terminate gracefully, then force termination within a total
five-second harness cleanup budget. This harness budget does not extend the
library's one-second resource cleanup contract. Other containers/processes are
never selected by name patterns or killed. Output capture is bounded to 16 MiB
per stream; overflow fails while cleanup remains active.

## WMB-N03 — Results and acceptance

`result.json`, schema `wotex.modbus.software@2`, records source commit/tree and
file hashes, dependency mode and exact dependency hashes, fixture/manifest and
binary hashes, Elixir/OTP versions, exact argv, test seed, requirement/case IDs,
test/peer exit codes, outcome, log hashes, stress measurements and owned-resource
counts. No credentials, machine-specific source paths or raw process state enter
publishable evidence. Failed setup and failed cleanup retain failure results.
Results identify independent-stack, malformed-peer and injected-contract lanes
separately. A passing result requires zero remaining owned sockets, contexts,
mappings and containers, plus clean required ASan/UBSan/leak diagnostics.

ExUnit task tests cover valid reuse; missing/corrupt manifest; changed source or
binary; traversal archive; missing executable; readiness timeout; absent peer
response; test crash; excessive output; owner death; and cleanup failure. Each
asserts both a non-success result where applicable and zero owned resources.
Run the software task on Elixir 1.18.4/OTP 27.3.4.15 and
Elixir 1.20.2/OTP 29.0.4, with isolated build and PLT directories.

Acceptance requires both toolchains, a clean committed-source
`WOTEX_PATH_DEPS=1 mix check --no-retry`, and out-of-tree package compilation.
Artifact adoption without path dependencies is a separate explicitly recorded
consumer result. Existing Python-run results do not validate these Mix tasks.
RTU, Modbus Security, hardware, publication and consumer migration remain outside
this profile.
