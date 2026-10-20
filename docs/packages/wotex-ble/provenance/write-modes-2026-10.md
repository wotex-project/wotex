# Explicit BlueZ write-mode evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source parent: `3340ecd6c53215b024184b5976199b18a22e190b`; the complete dirty input identities below bind the
new write-mode implementation before its owning commit.
Owner: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.2.0.

The explicit mode reaches the facade, low-level message, write-only Form
selector, Runtime Result and native operation without fallback. A command
returns exactly native queue evidence and Runtime `:accepted`; acknowledged
writes retain `:written` and `:ok`. Current MTU and command permissions are
checked before the submission event or D-Bus call. Current generation, one
original deadline and existing finite queue/custody remain authoritative.

## Executed checks

Commands ran from the repository root on host Elixir 1.20.2 / OTP 29.0.4:

```text
mix pkg wotex-ble test test/wotex/ble/write_mode_test.exs test/wotex/ble/procedure_test.exs test/wotex/ble/mapping_test.exs test/wotex/ble/runtime_integration_test.exs test/wotex/ble/dbus_bridge_test.exs
mix native.lint --package wotex-ble --fix
mix native.test --package wotex-ble --workspace <owned-absolute-workspace>
mix check.fast --package wotex-ble
MIX_ENV=test mix pkg wotex-ble run --no-start --no-compile bin/check_archive.exs
mix docs.pkg wotex-ble
mix docs.check
mix workspace
```

The focused suite passes 52 cases: one property and 51 tests. The new six-case
suite covers closed options and replies, one-shot refusal before executable
invocation, exact command/request routing, loss/malformed replies without
retry, unsent queued expiry, and real Runtime `:accepted` payload preservation.
The package fast gate passes compilation, formatting, strict Credo, all 308
cases (nine doctests, seventeen properties and 282 tests) and native formatting.
Its 58 hardware/software/interop cases are excluded from that ordinary suite;
the real native lane below separately executes its 41 interop tests.
ExDoc builds successfully and every repository Markdown link resolves. The root
workspace gate passes after restoring the required completed-contract wording
in usage rules; the focused layout regression also passes both cases.

The Linux ARM64 native suite passes all 41 cases through the pinned private
D-Bus peer and actual built SDK executable. The command procedure tests observe
exact `command` versus `request` options and distinct flags; empty and exact
payload bounds for MTUs 23, 24, 247 and 517; one-over and missing/invalid MTU
refusal; wrong native MTU types; an MTU-only change fencing the former
discovery generation; original deadline, cancellation, one completion and no
replay after a late reply. Existing native request-only, owner, sender, discovery, pairing and
stream cases remain green. The first native invocation refused a missing bind
workspace before running tests; creating the owned directory resolved that
setup failure without changing the test selection.

The ordinary archive check passes its allowlist and out-of-tree compilation.
Archive SHA-256: `599d6a9411c245c79e5baa4daefde99dfc4140adb47092bbec6dc7ab970237f6`.
This is package contents/compilation evidence, not the independent installed
write-mode archive consumer required by WBL08-T5.

## Native identities

Linux image: `wotex-native-linux:977d7ed5daf3af46`. The pinned libdbus build is
1.16.2. Native source-tree identity: `d20913ccdb912a9c8aee41942bd42dc4635aab1a60c5fed2f2db758e867d87b4`.
Build manifest SHA-256: `aa3bce5dec3b0e5df9e01b77234efad198e8c556589bb4ca82edaccaded4f9ad`.
The build toolchain is `{"executables":{"c++":{"path":"/usr/bin/c++","sha256":"fc02363794280f404c6ca6f5da1c8fe469be902e9de140d35d8573bb3393f53b"},"cc":{"path":"/usr/bin/cc","sha256":"a20520ee21543f243d40636a9181a142c45ecd989de31ab86b99a8ea5ada870d"},"cmake":{"path":"/usr/bin/cmake","sha256":"05e8a03ddf5a5075139760bcf4fc5bb73112246c5cd796dc85854589cfa502cb"},"ninja":{"path":"/usr/bin/ninja","sha256":"6e1421e278aab982b02cb43c68957ae8d3580444ad865323ff2823e243d7ed30"},"pkg-config":{"path":"/usr/bin/pkg-config","sha256":"b21b58e97876992968c82d823d74034abbc6a4176f8c9d5f2e0400f343e73fc1"},"readelf":{"path":"/usr/bin/readelf","sha256":"6bca2bbd23b072db9e9a19ae0e65cf7b7c15c08a3c2cf01dd56453e1ac9340b1"},"xz":{"path":"/usr/bin/xz","sha256":"296a7eaf0ac8cc4f37bd29f8fded9c768ed60fc646f64333e83e4f3a9148451d"}},"target_triple":"aarch64-linux-gnu","versions":{"version_cc":"cc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0\nCopyright (C) 2023 Free Software Foundation, Inc.\nThis is free software; see the source for copying conditions.  There is NO\nwarranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.","version_cmake":"cmake version 3.28.3\n\nCMake suite maintained and supported by Kitware (kitware.com/cmake).","version_cxx":"c++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0\nCopyright (C) 2023 Free Software Foundation, Inc.\nThis is free software; see the source for copying conditions.  There is NO\nwarranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.","version_ninja":"1.11.1","version_pkg_config":"1.8.1","version_readelf":"GNU readelf (GNU Binutils for Ubuntu) 2.42\nCopyright (C) 2024 Free Software Foundation, Inc.\nThis program is free software; you may redistribute it under the terms of\nthe GNU General Public License version 3 or (at your option) any later version.\nThis program has absolutely no warranty.","version_xz":"xz (XZ Utils) 5.4.5\nliblzma 5.4.5"}}`.
The existing manifest records exact source, loader and dependency inputs. These are normal builds; no ASan/UBSan or clang-tidy result is claimed.

| Executed artifact | SHA-256 |
| --- | --- |
| `output/bin/wotex-ble-host` | `7e2d295e466dfb83ded348ff717a2738bbed67ffb3c45d36bb35ef14fb5fef80` |
| `output/bin/wotex-ble-guardian` | `883e82dd24e166f6092e9778d2cbe8ff14c8f5ccaddc86b96dd54296d8675686` |
| `output/bin/dbus-daemon` | `c4c13644d73872faa87eb54f3dfddb37dd9781bfe9789c257047d57f497dcd67` |
| `output/lib/libdbus-1.so.3` | `fa3842cb351c58fdff864fdfddb4e921891d0a95b5bbcc654406bf2baa927569` |

## Source identities

Paths are relative to `packages/wotex-ble`.

| File | SHA-256 |
| --- | --- |
| `lib/wotex/ble.ex` | `055e529424e75a7c825aae2479a11dbc2790d055b0e7f76c1abd5e385a603ba5` |
| `lib/wotex/ble/address.ex` | `ffc1e22e3f762106250cba0a29c9e1ebac3b7144330c1311891a2d0deea7bfc3` |
| `lib/wotex/ble/procedure.ex` | `bf6c95dbe54dcb18e9eea54da7e65d0c5bccd647d0e31af8a681f491d311edc9` |
| `lib/wotex/ble/bluez.ex` | `1c30933ba9dcf83d0eb012d8d3e04df75f8679cf2e180d8f7893706f33e3a751` |
| `lib/wotex/ble/bluez/connection.ex` | `e9798c2cd6d31e23aa80ecef15ca49fc15b3f81ce36bdee2daa71f438ef36608` |
| `lib/wotex/ble/bluez/response.ex` | `4dd05b24a288b1fa62faec10b3dccb811a2c59b24d65e5e778df5831701174ee` |
| `lib/wotex/ble/mapping.ex` | `e7e7a1c15d12e9e5bda727960d60db6a91f8b3c99ad5665cc50a8c24f2f70015` |
| `lib/wotex/ble/transport.ex` | `0c478750d5f3e08f4c20e13e23b5d09b85edc1c132236d83b3aca5b6303b8237` |
| `priv/bluez/native/frame.hpp` | `ad00432cb9b6ceffdd74f77abe815d52ee177fb26a6310245af8170e0cb4375e` |
| `priv/bluez/native/host.hpp` | `248daaad332c93a185c87dbbdcd6618afa776418b248f3aa72d355b0a2ebbe66` |
| `priv/bluez/native/objects.hpp` | `f58540e5b10636bbf4f1e9d829cca26ed7ab6af2bbc5f6a0bf51ad9a860c9fc2` |
| `priv/bluez/native/discovery.hpp` | `a184cdbfe75d19c5a54df06e268952e3e2365642dfdf2dfa1165b299d6f1ef5f` |
| `priv/bluez/native/procedures.hpp` | `11bf549aaa6b632710da14fe6e3add897a0e20ee40c472278d7a705426dfd322` |
| `test/native/procedures_test.hpp` | `cd4064bf795d5fd35cd3438d069a66ae7bc26cf23fe199e0daed3fcb2e76d11f` |
| `test/native/scripted_host.cpp` | `df2320255261e2d98a0eb0f48e6c8d68325b5357a8f0160333806692c54a0f93` |
| `test/wotex/ble/write_mode_test.exs` | `950ac95540cf2f589a95a2994daa2fbaaa5305bf502ec69bd5ff26944e057372` |
| `mix.lock` | `50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4` |

## Qualification and cleanup

The native runner removed its owned container. Its disposable workspace and the
archive check's temporary artifacts were removed after recording identities;
reusable dependency/build/image caches were retained. This run did not execute
BlueZ virtual controllers, a real radio/device, CoreBluetooth, a second
architecture, sanitizer, Dialyzer or the full package coverage gate. Those checks
are not inferred from private D-Bus or scripted protocol peers.

WBL.08 remains partial. Independent archive/controller qualification,
CoreBluetooth permission/sleep/readiness and installed-host lifecycle, and
physical qualification remain open. An accepted command grants neither consumer
authority nor canonical Property truth. No release or dependency pin changed.
