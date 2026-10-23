"""Independent PyModbus peer; its explicit register image comes from the Elixir test."""

import asyncio
import json
import signal
from pathlib import Path

from pymodbus.server import ModbusTcpServer
from pymodbus.simulator import DataType, SimData, SimDevice


async def main():
    model = json.loads(Path("model.json").read_text(encoding="utf-8"))
    names = ("coils", "discrete_inputs", "holding_registers", "input_registers")
    blocks = tuple(
        [SimData(0, values=model[name], datatype=DataType.BITS if index < 2 else DataType.REGISTERS)]
        for index, name in enumerate(names)
    )
    device = SimDevice(1, simdata=blocks)
    server = ModbusTcpServer(device, address=("0.0.0.0", 5020))
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stopped.set)
    try:
        await server.serve_forever(background=True)
        print("WOTEX_LAB_MODBUS_READY", flush=True)
        await stopped.wait()
    finally:
        await server.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
