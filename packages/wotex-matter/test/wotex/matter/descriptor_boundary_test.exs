defmodule Wotex.Matter.DescriptorBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.{Descriptor, Error, TLV}

  @identity %{fabric_id: 1, node_id: 2, endpoint: 1}
  @acl Map.merge(@identity, %{cluster: 31, member: 0})

  test "WMA-S01 generated descriptor round trips preserve native scalar and structured values" do
    for {kind, cluster, member, operation, values} <- [
          {:attribute, 0x0201, 0, :read, [nil, -32_768, 0, 32_767]},
          {:attribute, 0x0201, 0x12, :write, [-32_768, 0, 32_767]},
          {:attribute, 0x0201, 0x1C, :write, [0, 255]},
          {:attribute, 6, 0, :read, [false, true]},
          {:command, 6, 1, :invoke, [%{}]},
          {:attribute, 0x001D, 0, :read, [[], [%{device_type: 0xFFFFFFFF, revision: 65_535}]]},
          {:attribute, 0x001D, 1, :read, [[], [0, 0x7FFF, 0x10000, 0xFFF47FFF]]},
          {:attribute, 0x001D, 3, :read, [[], [0, 0xFFFE]]},
          {:event, 0x0039, 3, :read, [%{reachable: false}, %{reachable: true}]},
          {:attribute, 0x003C, 0, :read, [0, 1, 2]},
          {:attribute, 0x003C, 1, :read, [nil, 1, 254]},
          {:attribute, 0x003C, 2, :read, [nil, 1, 65_534]}
        ],
        value <- values do
      path = Map.merge(@identity, %{cluster: cluster, member: member})
      assert {:ok, element} = Descriptor.to_element(kind, path, operation, value)
      assert {:ok, bytes} = TLV.encode([element])
      assert {:ok, [decoded]} = TLV.decode(bytes)
      assert {:ok, ^value} = Descriptor.from_element(kind, path, operation, decoded)
    end
  end

  test "WMA-S01 descriptor reads reject incompatible types and unknown members" do
    for {cluster, member, element} <- [
          {0x003C, 0, scalar(:u8, 3)},
          {0x003C, 1, scalar(:u8, 0)},
          {0x003C, 1, scalar(:u8, 255)},
          {0x003C, 2, scalar(:u16, 0)},
          {0x003C, 2, scalar(:u16, 65_535)},
          {0x001D, 1, scalar(:array, [scalar(:u16, 6)])},
          {0x001D, 0, scalar(:array, [scalar(:structure, [])])},
          {0x0201, 0, scalar(:u16, 0)},
          {0xFFFF, 0, scalar(:boolean, false)}
        ] do
      path = Map.merge(@identity, %{cluster: cluster, member: member})

      assert {:error, %Error{effect: :none}} =
               Descriptor.from_element(:attribute, path, :read, element)
    end
  end

  test "WMA-S05 ACL round trips distinguish null selectors empty lists and optional fields" do
    for subjects <- [nil, [], [0, 0xFFFFFFFFFFFFFFFF]],
        targets <- [
          nil,
          [],
          [%{cluster: 31, endpoint: 0, device_type: nil}],
          [%{cluster: nil, endpoint: nil, device_type: 0xFFFFFFFF}]
        ],
        auxiliary <- [0, 1],
        fabric <- [1, 254] do
      entries = [
        %{
          privilege: 5,
          auth_mode: 2,
          subjects: subjects,
          targets: targets,
          auxiliary_type: auxiliary,
          fabric_index: fabric
        }
      ]

      assert {:ok, element} = Descriptor.to_element(:attribute, @acl, :read, entries)
      assert {:ok, ^entries} = Descriptor.from_element(:attribute, @acl, :read, element)

      assert {:error, %Error{code: :invalid_value, effect: :none}} =
               Descriptor.validate_element(:attribute, @acl, :write, element)

      writable = Enum.map(entries, &Map.delete(&1, :fabric_index))
      assert {:ok, writable_element} = Descriptor.to_element(:attribute, @acl, :write, writable)
      assert {:ok, ^writable} = Descriptor.from_element(:attribute, @acl, :write, writable_element)
    end
  end

  test "WMA-S05 ACL inputs reject invalid selectors bounds and fields" do
    entry = %{privilege: 5, auth_mode: 2, subjects: nil, targets: nil}

    for invalid <- [
          nil,
          Map.put(entry, :subjects, false),
          Map.put(entry, :targets, false),
          Map.put(entry, :subjects, List.duplicate(1, 65)),
          Map.put(entry, :targets, List.duplicate(%{}, 65)),
          Map.put(entry, :targets, [false]),
          Map.put(entry, :auxiliary_type, 2),
          Map.put(entry, :fabric_index, 0),
          Map.put(entry, :fabric_index, 255),
          Map.put(entry, :targets, [%{cluster: nil, endpoint: nil, device_type: nil}]),
          Map.put(entry, :targets, [%{cluster: 6, endpoint: 1, device_type: 1}]),
          Map.put(entry, :targets, [%{cluster: 6, endpoint: 65_535, device_type: nil}])
        ] do
      assert {:error, %Error{code: :invalid_value, effect: :none}} =
               Descriptor.to_element(:attribute, @acl, :write, [invalid])
    end

    assert {:error, %Error{code: :invalid_value}} =
             Descriptor.to_element(:attribute, @acl, :read, List.duplicate(entry, 65))
  end

  test "WMA-S05 well-formed TLV cannot bypass the ACL field schemas" do
    entry = %{privilege: 5, auth_mode: 2, subjects: nil, targets: nil, auxiliary_type: 1}
    assert {:ok, element} = Descriptor.to_element(:attribute, @acl, :write, [entry])

    for {tag, type, value} <- [
          {1, :u16, 5},
          {2, :u16, 2},
          {3, :boolean, false},
          {4, :boolean, false},
          {4, :array, [scalar(:boolean, false)]},
          {5, :u16, 1}
        ] do
      changed = replace_field(element, tag, scalar(type, value, {:context, tag}))
      assert {:ok, _} = TLV.validate_element(changed)

      assert {:error, %Error{code: :invalid_value}} =
               Descriptor.validate_element(:attribute, @acl, :write, changed)
    end

    target =
      scalar(:structure, [
        scalar(:boolean, false, {:context, 0}),
        scalar(:null, nil, {:context, 1}),
        scalar(:u32, 1, {:context, 2})
      ])

    changed = replace_field(element, 4, scalar(:array, [target], {:context, 4}))

    assert {:error, %Error{code: :invalid_value}} =
             Descriptor.validate_element(:attribute, @acl, :write, changed)

    assert {:error, %Error{code: :invalid_value}} =
             Descriptor.validate_element(:attribute, @acl, :write, scalar(:array, [scalar(:u8, 1)]))
  end

  defp replace_field(%{value: [entry]} = element, tag, replacement) do
    fields =
      Enum.map(entry.value, fn field ->
        if field.tag == {:context, tag}, do: replacement, else: field
      end)

    %{element | value: [%{entry | value: fields}]}
  end

  defp scalar(type, value, tag \\ :anonymous), do: %{tag: tag, type: type, value: value}
end
