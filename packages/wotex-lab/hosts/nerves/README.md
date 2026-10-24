# WoTEx Lab Nerves host

This is the explicit Raspberry Pi 4 firmware source owned by WLB.08. It pins
Nerves 1.15.0, `nerves_system_rpi4` 2.1.2 and the aarch64 toolchain closure in
`mix.lock`. Boot starts one bounded `Wotex.Lab` instance and nothing else: no
experiment, listener, device discovery, model, database or physical effect.

The ordinary host cohort uses workspace dependencies and does not claim a
firmware boot:

```sh
WOTEX_PATH_DEPS=1 MIX_TARGET=host mix deps.get
WOTEX_PATH_DEPS=1 MIX_TARGET=host mix test
```

Its gate, `WOTEX_PATH_DEPS=1 MIX_TARGET=host mix check --no-retry`, checks the
locked and unused dependencies, compiles with warnings as errors and runs the
format check, strict Credo and the host test (`.check.exs`). It needs no
Nerves toolchain. The Lab's full gate (`mix pkg wotex-lab check --no-retry`)
runs it as its `nerves_host` tool.

An rpi4 source build requires the operator-installed Nerves host prerequisites,
including `fwup`, SquashFS, coreutils, xz and pkg-config
([Nerves installation](https://hexdocs.pm/nerves/1.15.0/installation.html)),
and the pinned `nerves_bootstrap` archive:

```sh
mix archive.install hex nerves_bootstrap 1.15.0
WOTEX_PATH_DEPS=1 MIX_TARGET=rpi4 mix deps.get
WOTEX_PATH_DEPS=1 MIX_TARGET=rpi4 mix firmware
```

The project requires and starts `nerves_bootstrap` 1.15.0 only for firmware
targets; the ordinary host gate needs no bootstrap archive. The supplied
`rel/vm.args.eex` selects the supported Elixir CLI startup, strict code paths,
idle scheduler behavior and the Nerves runtime heartbeat. It loads no extra
console script. Both the source archive and its input digest include that file.

Verify a built bundle without applying it to media:

```sh
fwup --verify -i _build/rpi4_dev/nerves/images/wotex_lab_nerves.fw
fwup --metadata -i _build/rpi4_dev/nerves/images/wotex_lab_nerves.fw
```

These checks establish archive integrity, not a trusted signature or a boot.
Workspace mode is source evidence only. A publishable production firmware must
resolve released WoTEx Hex packages with `WOTEX_PATH_DEPS` unset and record the
resulting archive and firmware digests. Burning media and uploading firmware are
destructive/deployment actions and remain manual.

After boot, an attached operator explicitly runs:

```elixir
WotexLabNerves.Smoke.run()
```

The smoke uses `Nx.BinaryBackend`, returns an inert thermal Action proposal and
reads a simulated Property through two separately owned loopback Thing
processes. It invokes no Action and opens no socket. Its evidence carries the
compiled target, source/lock digests, dependency archive checksums where present
and cleanup state. The rpi4 boot assertion is `:not_run` on a host build.

The checked-in target source and host test do not claim a prebuilt image,
offline boot, physical reconnect or on-device result. Those require a released
artifact and Raspberry Pi 4 evidence. The explicit source cross-build assembles
the firmware bundle after the documented host prerequisites are provisioned.
Neither assembly nor archive integrity establishes physical execution.
