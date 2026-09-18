defmodule Wotex.Matter.Bench.Values do
  @moduledoc false

  # Admitted Descriptor values of growing size: one Thermostat setpoint, a
  # Descriptor ServerList and an AccessControl ACL. Each input carries the
  # schema value, its anonymous TLV element and the encoded TLV bytes.

  alias Wotex.Matter.{Descriptor, TLV}

  @setpoint %{fabric_id: 1, node_id: 0x1234, endpoint: 1, cluster: 0x0201, member: 0x0012}
  @server_list %{fabric_id: 1, node_id: 0x1234, endpoint: 1, cluster: 0x001D, member: 0x0001}
  @acl %{fabric_id: 1, node_id: 0x1234, endpoint: 0, cluster: 0x001F, member: 0x0000}

  @spec inputs() :: %{String.t() => map()}
  def inputs do
    %{
      "i16 setpoint" => input(:attribute, @setpoint, :write, 2150),
      "ServerList of 64 clusters" => input(:attribute, @server_list, :read, clusters(64)),
      "ACL of 32 entries" => input(:attribute, @acl, :write, acl(32))
    }
  end

  defp input(kind, path, operation, value) do
    {:ok, element} = Descriptor.to_element(kind, path, operation, value)
    {:ok, bytes} = TLV.encode([element])

    %{
      kind: kind,
      path: path,
      operation: operation,
      value: value,
      element: element,
      bytes: bytes
    }
  end

  defp clusters(count), do: Enum.to_list(0x0003..(0x0003 + count - 1))

  defp acl(count) do
    Enum.map(1..count, fn index ->
      %{
        privilege: rem(index, 5) + 1,
        auth_mode: 2,
        subjects: Enum.map(0..3, &(0x0000_0001_0000_0000 + index * 4 + &1)),
        targets: [
          %{cluster: 0x0006, endpoint: rem(index, 8) + 1, device_type: nil},
          %{cluster: nil, endpoint: nil, device_type: 0x0100}
        ]
      }
    end)
  end
end
