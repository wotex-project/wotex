Code.require_file("../../support/software/bridge_model.exs", __DIR__)

defmodule Wotex.Matter.SoftwareBridgeModelTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{SoftwareBridgeModel, SoftwareManifest}

  @model Path.expand("../../support/software/bridge-model-zap.json", __DIR__)
  @sources Path.expand("../../support/software/sources.json", __DIR__)
  @root Path.expand("../../..", __DIR__)

  test "the explicit model task rejects missing, duplicate and reordered inputs" do
    for arguments <- [
          [],
          ["--sdk", "/absolute/sdk"],
          ["--sdk", "/absolute/sdk", "--sdk", "/absolute/sdk"],
          ["--tools", "/absolute/tools", "--sdk", "/absolute/sdk", "--workspace", "/absolute/out"]
        ] do
      assert_raise Mix.Error, "invalid_bridge_model_arguments", fn ->
        Mix.Tasks.Wotex.Matter.Bridge.Model.run(arguments)
      end
    end

    assert_raise Mix.Error, "invalid_workspace", fn ->
      Mix.Tasks.Wotex.Matter.Bridge.Model.run([
        "--sdk",
        "relative/sdk",
        "--tools",
        "/absolute/tools",
        "--workspace",
        "/absolute/out"
      ])
    end
  end

  test "the reproducible model pins the independent server generation inputs" do
    profile = SoftwareBridgeModel.profile()
    model = SoftwareManifest.read(@model)
    assert :ok = SoftwareBridgeModel.verify!(model)
    assert SoftwareManifest.digest(@model) == profile["model_sha256"]
    assert SoftwareManifest.digest(@sources) == profile["source_manifest_sha256"]
    assert SoftwareManifest.read(@sources)["tools"] == profile["tools"]
    assert profile["sdk_revision"] == SoftwareManifest.sdk_revision()
    assert profile["sdk_archive_sha256"] == SoftwareManifest.sdk_sha256()
    assert profile["container_image"] == SoftwareManifest.image()

    assert profile["test_attestation"]["build_defines"] == [
             "CHIP_DEVICE_CONFIG_DEVICE_VENDOR_ID=0xFFF1",
             "CHIP_DEVICE_CONFIG_DEVICE_PRODUCT_ID=0x8001"
           ]

    for {path, digest} <- profile["generator_sources"] do
      assert SoftwareManifest.digest(Path.join(@root, path)) == digest
    end

    assert map_size(profile["generated_sha256"]) == 7
    assert profile["device_types"]["light"]["clusters"] == [3, 4, 6, 29, 57, 98]
    assert profile["device_types"]["temperature_sensor"]["clusters"] == [3, 29, 57, 1026]
    assert profile["dummy_endpoint"]["enabled_at_runtime"] == false
    assert Enum.map(model["endpoints"], & &1["endpointId"]) == [0, 1, 2]
  end

  test "missing mandatory commands and attributes cannot become an accepted model" do
    model = SoftwareManifest.read(@model)

    for {cluster, commands, attributes} <- [
          {3, [0, 64], [0, 1]},
          {4, [0, 1, 2, 3, 4, 5], [0]},
          {6, [0, 1, 2, 64, 65, 66], [0, 0x4000, 0x4001, 0x4002, 0x4003]},
          {98, [0, 1, 2, 3, 4, 5, 6, 64], [1, 2]},
          {1026, [], [0, 1, 2]}
        ] do
      for id <- commands do
        invalid =
          change_cluster(model, cluster, fn definition ->
            Map.update!(definition, "commands", fn commands ->
              Enum.map(commands, fn command ->
                if command["source"] == "client" and command["code"] == id,
                  do: Map.put(command, "isEnabled", 0),
                  else: command
              end)
            end)
          end)

        assert_raise Mix.Error, "bridge_model_required_commands", fn ->
          SoftwareBridgeModel.verify!(invalid)
        end
      end

      for id <- attributes do
        invalid =
          change_cluster(model, cluster, fn definition ->
            Map.update!(definition, "attributes", fn attributes ->
              Enum.reject(attributes, &(&1["code"] == id))
            end)
          end)

        assert_raise Mix.Error, "bridge_model_required_attributes", fn ->
          SoftwareBridgeModel.verify!(invalid)
        end
      end
    end
  end

  test "light features and cluster revisions cannot drift to the example defaults" do
    model = SoftwareManifest.read(@model)

    for {attribute, value, error} <- [
          {0xFFFC, "0", "bridge_model_lighting_feature"},
          {0xFFFD, "7", "bridge_model_cluster_revision"}
        ] do
      invalid =
        change_cluster(model, 6, fn definition ->
          Map.update!(definition, "attributes", fn attributes ->
            Enum.map(attributes, fn entry ->
              if entry["code"] == attribute, do: Map.put(entry, "defaultValue", value), else: entry
            end)
          end)
        end)

      assert_raise Mix.Error, error, fn -> SoftwareBridgeModel.verify!(invalid) end
    end
  end

  test "changed SDK inputs are refused before a generation workspace is created" do
    root =
      Path.join(System.tmp_dir!(), "matter-bridge-inputs-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    profile = SoftwareBridgeModel.profile()

    inputs =
      profile["inputs"]
      |> Map.merge(profile["test_attestation"]["inputs"])
      |> Map.merge(profile["independent_peer"]["inputs"])

    for {path, _} <- inputs do
      target = Path.join(root, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, "changed source")
    end

    workspace = Path.join(root, "generation")

    assert_raise Mix.Error, "bridge_model_source_mismatch", fn ->
      SoftwareBridgeModel.generate!(root, root, workspace)
    end

    refute File.exists?(workspace)
  end

  defp change_cluster(model, id, change) do
    [root, aggregator, dummy] = model["endpointTypes"]

    clusters =
      Enum.map(dummy["clusters"], fn cluster ->
        if cluster["code"] == id, do: change.(cluster), else: cluster
      end)

    Map.put(model, "endpointTypes", [root, aggregator, Map.put(dummy, "clusters", clusters)])
  end
end
