alias Wotex.BLE.{Characteristic, UUID}

# The Temperature characteristic (0x2A6E) as an integer and as short text, and
# a synthetic 128-bit vendor identity. ATT carries SIG identities as two
# octets and vendor identities as 16.
service_path = "/org/bluez/hci0/dev_00_00_5E_00_53_01/service0010"

inputs =
  Map.new(
    [
      {"16-bit integer", 0x2A6E, <<0x2A6E::16-little>>},
      {"16-bit text", "0x2A6E", <<0x2A6E::16-little>>},
      {"128-bit text", "a1b2c3d4-0002-4e5f-8a9b-0123456789ab",
       <<0xA1B2C3D4_0002_4E5F_8A9B_0123456789AB::128-little>>}
    ],
    fn {label, uuid, att} ->
      discovered = %{
        service_uuid: "181a",
        characteristic_uuid: uuid,
        service_path: service_path,
        object_path: service_path <> "/char0011",
        flags: ["read", "write", "notify"],
        generation: 3,
        handle: 17
      }

      {label, %{uuid: uuid, att: att, discovered: discovered}}
    end
  )

Benchee.run(
  %{
    "normalize" => fn %{uuid: uuid} -> {:ok, _} = UUID.normalize(uuid) end,
    "encode ATT UUID" => fn %{uuid: uuid} -> {:ok, <<_::128>>} = UUID.encode(uuid) end,
    "decode ATT UUID" => fn %{att: att} -> {:ok, _} = UUID.decode(att) end,
    "admit discovered characteristic" => fn %{discovered: discovered} ->
      {:ok, _} = Characteristic.address(discovered)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/identity.md",
     title: "# UUID normalization and characteristic identity",
     description: """
     `Wotex.BLE.UUID.normalize/1`, `encode/1` and `decode/1` for the Bluetooth
     SIG Temperature characteristic (0x2A6E) as an integer and as `0x` text,
     and for a synthetic 128-bit vendor UUID in canonical text. `encode/1`
     always yields the 16-octet ATT form; `decode/1` takes the two-octet SIG
     form or the 16-octet vendor form. `Wotex.BLE.Characteristic.address/1`
     validates a discovered characteristic (both UUIDs, both D-Bus object paths,
     three flags, handle and generation) and returns its generation-bound
     `Wotex.BLE.Address`.
     """}
  ]
)
