# GATT procedures through the public API on a persistent BlueZ session, run by
# `mix native.bench --package wotex-ble --workspace /abs/dir` on a Linux host
# with the software lane's private bus, bluetoothd, virtual controllers and
# GATT peer (WOTEX_BLE_SOFTWARE_CONFIG). The peer's `value` characteristic
# holds 0x1234; the write stores the same value, so every read sees it.
Code.require_file("support/software.exs", __DIR__)

alias Wotex.BLE
alias Wotex.BLE.Bench.Software

socket = Software.control_socket!()
config = Software.command(socket, "reset")
{:ok, session} = BLE.connect(Software.options(config))

try do
  {:ok, page} = BLE.discover(session)
  address = Software.target(page, :value)
  {:ok, <<0x34, 0x12>>} = BLE.read(session, address)

  Benchee.run(
    %{
      "read 2 bytes" => fn -> {:ok, <<0x34, 0x12>>} = BLE.read(session, address) end,
      "read uint16" => fn -> {:ok, 4660} = BLE.read(session, address, value_type: :uint16) end,
      "write uint16 with response" => fn ->
        {:ok, :written} = BLE.write(session, address, 4660, value_type: :uint16)
      end
    },
    warmup: 1,
    time: 5,
    formatters: Software.formatters()
  )

  %{"values" => %{"value" => "3412"}} = Software.command(socket, "stats")
after
  :ok = BLE.disconnect(session)
end
