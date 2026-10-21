Code.require_file("../support/software/exposed_bridge.exs", __DIR__)

defmodule Wotex.Matter.ExposedBridgeCommandsInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.SoftwareExposedBridge

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 120_000

  test "authenticated SDK command families preserve native responses and approved snapshots" do
    fixture = fixture()
    root = SoftwareExposedBridge.prepare!(fixture, "commands")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, owner} = SoftwareExposedBridge.start_link(parent: self(), fixture: fixture, root: root)
    on_exit(fn -> if Process.alive?(owner), do: GenServer.stop(owner) end)

    try do
      pair(fixture, root, 780_001)

      {without_key, _} = invoke(fixture, root, 4, 0, ["groups", "add-group", "7", ""])
      assert without_key =~ "status: 126"
      provision_groups(fixture, root)

      assert {:ok, :applied} =
               SoftwareExposedBridge.call(
                 owner,
                 {:observe,
                  %{thing: <<0, 1>>, endpoint: 3, reachable: true, on_off: false, temperature: nil}}
               )

      extension = ~s([{"clusterID":6,"attributeValueList":[{"attributeID":0,"valueUnsigned8":1}]}])

      cases = [
        {4, 0, ["groups", "add-group", "7", ""], ["groupID: 7"]},
        {3, 0, ["identify", "identify", "30"], []},
        {4, 5, ["groups", "add-group-if-identifying", "8", ""], []},
        {4, 1, ["groups", "view-group", "7"], ["groupID: 7"]},
        {4, 2, ["groups", "get-group-membership", "[7,8]"], ["groupList: 2 entries"]},
        {6, 1, ["onoff", "on"], []},
        {6, 0, ["onoff", "off"], []},
        {6, 2, ["onoff", "toggle"], []},
        {6, 64, ["onoff", "off-with-effect", "0", "0"], []},
        {6, 65, ["onoff", "on-with-recall-global-scene"], []},
        {6, 66, ["onoff", "on-with-timed-off", "0", "300", "20"], []},
        {98, 0, ["scenesmanagement", "add-scene", "7", "1", "0", "", extension],
         ["groupID: 7", "sceneID: 1"]},
        {98, 1, ["scenesmanagement", "view-scene", "7", "1"],
         ["groupID: 7", "sceneID: 1", "ValueUnsigned8: 1"]},
        {98, 4, ["scenesmanagement", "store-scene", "7", "2"], ["sceneID: 2"]},
        {98, 1, ["scenesmanagement", "view-scene", "7", "2"], ["sceneID: 2", "ValueUnsigned8: 0"]},
        {98, 5, ["scenesmanagement", "recall-scene", "7", "1"], []},
        {98, 6, ["scenesmanagement", "get-scene-membership", "7"],
         ["groupID: 7", "sceneList: 2 entries"]},
        {98, 64, ["scenesmanagement", "copy-scene", "0", "7", "1", "7", "3"],
         ["sceneIdentifierFrom: 1"]},
        {98, 1, ["scenesmanagement", "view-scene", "7", "3"], ["sceneID: 3", "ValueUnsigned8: 1"]},
        {98, 2, ["scenesmanagement", "remove-scene", "7", "3"], ["sceneID: 3"]},
        {98, 3, ["scenesmanagement", "remove-all-scenes", "7"], ["groupID: 7"]},
        {98, 6, ["scenesmanagement", "get-scene-membership", "7"], ["sceneList: 0 entries"]},
        {4, 3, ["groups", "remove-group", "7"], ["groupID: 7"]},
        {4, 4, ["groups", "remove-all-groups"], []},
        {4, 2, ["groups", "get-group-membership", "[]"], ["groupList: 0 entries"]},
        {3, 64, ["identify", "trigger-effect", "0", "0"], []},
        {3, 0, ["identify", "identify", "0"], []}
      ]

      seen =
        for {cluster, member, arguments, fields} <- cases do
          {output, request} = invoke(fixture, root, cluster, member, arguments)
          for field <- fields, do: assert(output =~ field, output)

          if (cluster == 4 and member in [0, 1, 3]) or
               (cluster == 98 and member in [0, 1, 2, 3, 4, 6, 64]) do
            assert Regex.match?(~r/\bstatus: 0\b/, output), output
          end

          {request.path.cluster, request.path.member}
        end

      assert MapSet.size(MapSet.new(seen)) == 22

      {output, status} =
        SoftwareExposedBridge.peer(fixture, root, ["onoff", "read", "on-off", "780001", "3"])

      assert status == 0, output
      assert output =~ "OnOff: FALSE"
      assert_receive {:bridge_policy, %{operation: :read}, _}, 1000
      assert_receive {:bridge_handler, _, :readproperty, "value", _}, 1000
      assert_receive {:bridge_approved, _, {:ok, :applied}}, 1000

      assert {:ok, %{pending: 0, observations: 0, probing: false}} =
               SoftwareExposedBridge.call(owner, :status)
    after
      assert :ok = SoftwareExposedBridge.call(owner, :close)
    end
  end

  test "two authenticated fabrics isolate Groups, Scenes and consumer authorization" do
    fixture = fixture()
    root = SoftwareExposedBridge.prepare!(fixture, "fabrics")
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, owner} =
      SoftwareExposedBridge.start_link(
        parent: self(),
        fixture: fixture,
        root: root,
        principals: [{55, 770_001, 780_001}, {56, 770_002, 780_002}]
      )

    on_exit(fn -> if Process.alive?(owner), do: GenServer.stop(owner) end)
    second = [fabric: 56, subject: 770_002, node: 780_002]

    try do
      pair(fixture, root, 780_001)
      provision_groups(fixture, root)
      {first, first_request} = invoke(fixture, root, 4, 0, ["groups", "add-group", "7", ""])
      assert first =~ "status: 0"

      {output, status} =
        SoftwareExposedBridge.peer(fixture, root, [
          "pairing",
          "open-commissioning-window",
          "780001",
          "1",
          "180",
          "1000",
          "3840"
        ])

      assert status == 0, output
      [_, code] = Regex.run(~r/Manual pairing code: \[([0-9]+)\]/, output)

      {output, status} =
        SoftwareExposedBridge.peer(
          fixture,
          root,
          ["pairing", "code", "780002", code],
          second
        )

      assert status == 0, output
      assert output =~ "Commissioning complete for node ID"
      provision_groups(fixture, root, second)

      {absent, second_request} =
        invoke(fixture, root, 4, 1, ["groups", "view-group", "7"], second)

      assert absent =~ "status: 139"
      assert first_request.principal.fabric_index != second_request.principal.fabric_index

      assert first_request.fabric_scope.root_public_key !=
               second_request.fabric_scope.root_public_key

      assert first_request.fabric_scope.noc_sha256 != second_request.fabric_scope.noc_sha256

      for {options, group} <- [{second, 8}, {second, 7}] do
        {output, _} =
          invoke(
            fixture,
            root,
            4,
            0,
            ["groups", "add-group", Integer.to_string(group), ""],
            options
          )

        assert output =~ "status: 0"
      end

      {absent, _} = invoke(fixture, root, 4, 1, ["groups", "view-group", "8"])
      assert absent =~ "status: 139"

      {added, _} = add_scene(fixture, root, 1, [])
      assert added =~ "status: 0"

      {absent, _} =
        invoke(fixture, root, 98, 1, ["scenesmanagement", "view-scene", "7", "1"], second)

      assert absent =~ "status: 139"
      {added, _} = add_scene(fixture, root, 0, second)
      assert added =~ "status: 0"

      for {options, value} <- [{[], 1}, {second, 0}] do
        {output, _} =
          invoke(fixture, root, 98, 1, ["scenesmanagement", "view-scene", "7", "1"], options)

        assert output =~ "status: 0"
        assert output =~ "ValueUnsigned8: #{value}"
      end

      {removed, _} = invoke(fixture, root, 4, 4, ["groups", "remove-all-groups"])
      assert removed =~ "Sending cluster"
      {absent, _} = invoke(fixture, root, 4, 1, ["groups", "view-group", "7"])
      assert absent =~ "status: 139"

      {absent, _} = invoke(fixture, root, 98, 1, ["scenesmanagement", "view-scene", "7", "1"])
      assert absent =~ "status: 133"

      {retained, _} =
        invoke(fixture, root, 98, 1, ["scenesmanagement", "view-scene", "7", "1"], second)

      assert retained =~ "status: 0"
      assert retained =~ "ValueUnsigned8: 0"

      assert :ok = SoftwareExposedBridge.call(owner, {:deny_fabric, 56})

      {output, status} =
        SoftwareExposedBridge.peer(
          fixture,
          root,
          ["groups", "remove-group", "8", "780002", "3"],
          second
        )

      assert status != 0
      assert output =~ "0x7e"
      assert_receive {:bridge_policy, denied, _}, 1000
      assert denied.fabric_scope == second_request.fabric_scope
      refute_receive {:bridge_handler, _, _, _, _}, 0
      {allowed, _} = invoke(fixture, root, 4, 0, ["groups", "add-group", "7", ""])
      assert allowed =~ "status: 0"

      {absent, _} = invoke(fixture, root, 98, 1, ["scenesmanagement", "view-scene", "7", "1"])
      assert absent =~ "status: 139"

      assert :ok = SoftwareExposedBridge.call(owner, {:allow_fabric, 56})
      {retained, _} = invoke(fixture, root, 4, 1, ["groups", "view-group", "8"], second)
      assert retained =~ "status: 0"

      {output, status} =
        SoftwareExposedBridge.peer(fixture, root, [
          "operationalcredentials",
          "remove-fabric",
          Integer.to_string(second_request.principal.fabric_index),
          "780001",
          "0"
        ])

      assert status == 0, output
      assert response(output) =~ "statusCode: 0"

      {output, status} =
        SoftwareExposedBridge.peer(
          fixture,
          root,
          ["groups", "view-group", "8", "780002", "3", "--timeout", "2"],
          second
        )

      assert status != 0, output
      refute_receive {:bridge_policy, _, _}, 0
      refute_receive {:bridge_handler, _, _, _, _}, 0
      {retained, _} = invoke(fixture, root, 4, 1, ["groups", "view-group", "7"])
      assert retained =~ "status: 0"

      assert {:ok, %{pending: 0, observations: 0, probing: false}} =
               SoftwareExposedBridge.call(owner, :status)
    after
      assert :ok = SoftwareExposedBridge.call(owner, :close)
    end
  end

  defp fixture do
    path = System.fetch_env!("WOTEX_MATTER_EXPOSED_BRIDGE_FIXTURE")
    Jason.decode!(File.read!(path))
  end

  defp pair(fixture, root, node, options \\ []) do
    {output, status} =
      SoftwareExposedBridge.peer(
        fixture,
        root,
        ["pairing", "onnetwork", Integer.to_string(node), "20202021"],
        options
      )

    assert status == 0, output
    assert output =~ "Commissioning complete for node ID"
  end

  defp provision_groups(fixture, root, options \\ []) do
    node = Keyword.get(options, :node, 780_001)

    key =
      Jason.encode!(%{
        groupKeySetID: 1,
        groupKeySecurityPolicy: 0,
        groupKeyMulticastPolicy: 0,
        epochKey0: "hex:00112233445566778899aabbccddeeff",
        epochStartTime0: 1,
        epochKey1: nil,
        epochStartTime1: nil,
        epochKey2: nil,
        epochStartTime2: nil
      })

    mappings = Jason.encode!(for group <- [7, 8], do: %{groupId: group, groupKeySetID: 1})

    for arguments <- [
          ["groupkeymanagement", "key-set-write", key],
          ["groupkeymanagement", "write", "group-key-map", mappings]
        ] do
      {output, status} =
        SoftwareExposedBridge.peer(
          fixture,
          root,
          arguments ++ [Integer.to_string(node), "0"],
          Keyword.take(options, [:fabric, :subject])
        )

      assert status == 0, output
    end
  end

  defp add_scene(fixture, root, value, options) do
    extension =
      Jason.encode!([
        %{clusterID: 6, attributeValueList: [%{attributeID: 0, valueUnsigned8: value}]}
      ])

    invoke(
      fixture,
      root,
      98,
      0,
      ["scenesmanagement", "add-scene", "7", "1", "0", "", extension],
      options
    )
  end

  defp invoke(fixture, root, cluster, member, arguments, options \\ []) do
    node = Keyword.get(options, :node, 780_001)
    peer_options = Keyword.take(options, [:fabric, :subject])

    {output, status} =
      SoftwareExposedBridge.peer(
        fixture,
        root,
        arguments ++ [Integer.to_string(node), "3"],
        peer_options
      )

    assert status == 0, output
    assert_receive {:bridge_policy, request, context}, 1000
    assert request.operation == :invoke
    assert request.path == %{endpoint: 3, cluster: cluster, member: member}
    assert request.thing == <<0, 1>>
    assert request.principal.auth_mode == :case
    assert request.principal.subject == Keyword.get(options, :subject, 770_001)
    assert request.fabric_scope.fabric_id == Keyword.get(options, :fabric, 55)
    assert request.fabric_scope.bridge_node == node
    assert context.metadata.matter_bridge.request == request
    assert {:tlv, bytes} = request.payload
    assert byte_size(bytes) in 2..65_536
    assert_receive {:bridge_handler, _, :invokeaction, name, handler_context}, 1000
    assert handler_context == context
    if name == "set", do: assert_receive({:bridge_approved, _, {:ok, :applied}}, 1000)
    {response(output), request}
  end

  defp response(output) do
    output
    |> String.replace(~r/\e\[[\d;]*m/, "")
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "[TOO]"))
    |> Enum.join("\n")
  end
end
