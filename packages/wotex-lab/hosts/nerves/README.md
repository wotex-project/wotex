# WoTEx Lab Nerves host

This is the explicit Raspberry Pi 4 firmware source owned by WLB.08. It pins
Nerves 1.15.0, `nerves_system_rpi4` 2.1.1 and the aarch64 toolchain closure in
`mix.lock`. Boot starts one bounded `Wotex.Lab` instance and nothing else: no
experiment, listener, device discovery, model, database or physical effect.

The ordinary host cohort uses workspace dependencies and does not claim a
firmware boot:

```sh
WOTEX_PATH_DEPS=1 MIX_TARGET=host mix deps.get
WOTEX_PATH_DEPS=1 MIX_TARGET=host mix test
```

An rpi4 source build requires the operator-installed Nerves host prerequisites,
including the `nerves_bootstrap` archive and `fwup`:

```sh
mix archive.install hex nerves_bootstrap 1.15.0
WOTEX_PATH_DEPS=1 MIX_TARGET=rpi4 mix deps.get
WOTEX_PATH_DEPS=1 MIX_TARGET=rpi4 mix firmware
```

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
artifact and Raspberry Pi 4 evidence; the current local cross-build reaches
firmware assembly but cannot finish it when the host lacks `fwup`.
