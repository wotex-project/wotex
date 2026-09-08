# Independent TCP interoperability

The fixture builds libmodbus v3.1.12 from commit
`9af6c16074df566551bca0a7c37443e48f216289`. It exposes a disposable in-memory
register map; never point this write/readback test at operational equipment.

```sh
docker build -t wotex-modbus-peer test/interop/libmodbus
docker run --rm --name wotex-modbus-peer -p 127.0.0.1:15020:1502 wotex-modbus-peer
WOTEX_PATH_DEPS=1 WOTEX_MODBUS_INTEROP_HOST=127.0.0.1 WOTEX_MODBUS_INTEROP_PORT=15020 mix test --include interop test/interop/modbus_test.exs
docker stop wotex-modbus-peer
```

The opt-in suite requires both environment variables. A missing peer, failed
write, wrong readback or timeout fails the test. The base image and apt build
packages are moving inputs; only the protocol peer source revision is pinned.
This is software interoperability evidence, not hardware certification.
