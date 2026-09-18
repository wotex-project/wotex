# Independent TCP interoperability

The software fixture builds libmodbus 3.1.12 at commit
`9af6c16074df566551bca0a7c37443e48f216289` with verified archive and native
artifact hashes. Its disposable in-memory register map runs in an explicitly
owned container with a loopback-only port.

```sh
mix pkg wotex-modbus wotex.software.build --workspace /absolute/disposable/workspace
mix pkg wotex-modbus wotex.software.run --workspace /absolute/disposable/workspace
```

Run these from the repository root; inside `packages/wotex-modbus` the
equivalent is `WOTEX_PATH_DEPS=1 mix wotex.software.build ...` and
`WOTEX_PATH_DEPS=1 mix wotex.software.run ...`.

The shell entry points `build_software.sh` and `run_software.sh` accept the same
absolute workspace as their sole positional argument and execute these Mix tasks
in `packages/wotex-modbus`; export `WOTEX_PATH_DEPS=1` before calling them.
The tasks verify the workspace manifest, run protocol/stress/fault ExUnit cases,
and retain JSON outcomes and log hashes. Required setup, missing replies and
unverified cleanup fail the run. Each supported toolchain needs a separate run.
No Python executable is required.

[WMB.07](../../../../docs/packages/wotex-modbus/specs/WMB.07-native-build-and-software-evidence.md) specifies
native ownership and acceptance. [Executable evidence](../../../../docs/packages/wotex-modbus/provenance/executable-evidence.md)
binds completed runs to exact source identities. The native guardian owns Docker
through create/start, and the task suite hard-kills a child BEAM VM during that
interval before asserting exact peer removal. This is software interoperability,
separate from physical-device certification.
