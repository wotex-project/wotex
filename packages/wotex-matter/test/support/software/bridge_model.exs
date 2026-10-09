Code.require_file("manifest.exs", __DIR__)
Code.require_file("command.exs", __DIR__)

defmodule Wotex.Matter.SoftwareBridgeModel do
  @moduledoc false

  alias Wotex.Matter.{SoftwareCommand, SoftwareManifest}

  @profile Path.join(__DIR__, "bridge-model.json")
  @root_clusters [0x001D, 0x001F, 0x0028, 0x0030, 0x0031, 0x0033, 0x003C, 0x003E, 0x003F]
  @dummy_clusters [0x0003, 0x0004, 0x0006, 0x001D, 0x0062, 0x0402]
  @revisions %{
    0x0003 => 6,
    0x0004 => 4,
    0x0006 => 6,
    0x001D => 3,
    0x001F => 3,
    0x0028 => 6,
    0x0030 => 2,
    0x0031 => 2,
    0x0033 => 3,
    0x003C => 1,
    0x003E => 2,
    0x003F => 3,
    0x0062 => 1,
    0x0402 => 6
  }
  @commands %{
    0x0003 => [0, 64],
    0x0004 => [0, 1, 2, 3, 4, 5],
    0x0006 => [0, 1, 2, 64, 65, 66],
    0x001D => [],
    0x0062 => [0, 1, 2, 3, 4, 5, 6, 64],
    0x0402 => []
  }
  @required_attributes %{
    0x0003 => [0, 1],
    0x0004 => [0],
    0x0006 => [0, 0x4000, 0x4001, 0x4002, 0x4003],
    0x001D => [0, 1, 2, 3],
    0x0062 => [1, 2],
    0x0402 => [0, 1, 2]
  }

  @spec profile() :: map()
  def profile, do: SoftwareManifest.read(@profile)

  @spec assemble!(String.t()) :: map()
  def assemble!(sdk) do
    profile = profile()

    unless SoftwareManifest.digest(Path.join(__DIR__, "sources.json")) ==
             profile["source_manifest_sha256"],
           do: Mix.raise("bridge_model_manifest_mismatch")

    inputs =
      profile["inputs"]
      |> Map.merge(profile["test_attestation"]["inputs"])
      |> Map.merge(profile["independent_peer"]["inputs"])

    for {path, digest} <- inputs do
      unless SoftwareManifest.digest(Path.join(sdk, path)) == digest,
        do: Mix.raise("bridge_model_source_mismatch")
    end

    bridge = read_zap(sdk, "examples/bridge-app/bridge-common/bridge-app.zap")
    lighting = read_zap(sdk, "examples/lighting-app/lighting-common/lighting-app.zap")
    all = read_zap(sdk, "examples/all-clusters-app/all-clusters-common/all-clusters-app.zap")
    [root, aggregator, dummy] = bridge["endpointTypes"]

    root = Map.update!(root, "clusters", &select_clusters(&1, @root_clusters))
    aggregator = Map.update!(aggregator, "clusters", &select_clusters(&1, [0x001D]))

    clusters =
      for id <- @dummy_clusters do
        source = if id in [0x0003, 0x0004, 0x0006], do: lighting, else: all

        source["endpointTypes"]
        |> Enum.flat_map(& &1["clusters"])
        |> Enum.find(&(&1["code"] == id and &1["side"] == "server"))
        |> normalize_cluster(id)
      end

    dummy = Map.put(dummy, "clusters", clusters)

    bridge
    |> Map.put("endpointTypes", [root, aggregator, dummy])
    |> Map.update!("endpoints", fn endpoints ->
      Enum.map(endpoints, &Map.put(&1, "parentEndpointIdentifier", nil))
    end)
  end

  @spec bytes(map()) :: binary()
  def bytes(model), do: Jason.encode!(model, pretty: true) <> "\n"

  @spec generate!(String.t(), String.t(), String.t()) :: :ok
  def generate!(sdk, tools, workspace) do
    model = assemble!(sdk)
    :ok = verify!(model)
    profile = profile()
    encoded = bytes(model)

    unless Base.encode16(:crypto.hash(:sha256, encoded), case: :lower) == profile["model_sha256"],
      do: Mix.raise("bridge_model_config_mismatch")

    tool = Enum.find(profile["tools"], &(&1["name"] == "zap"))

    unless SoftwareManifest.digest(Path.join(tools, "zap/zap-cli")) == tool["sha256"],
      do: Mix.raise("bridge_model_tool_mismatch")

    workspace = SoftwareManifest.arguments(["--workspace", workspace], File.cwd!())
    File.mkdir!(workspace)
    File.write!(Path.join(workspace, "bridge-app.zap"), encoded, [:exclusive])

    for {templates, directory} <- [
          {"app-templates.json", "cpp"},
          {"matter-idl-server.json", "idl"}
        ] do
      output =
        SoftwareCommand.run!(
          "docker",
          [
            "run",
            "--rm",
            "--platform",
            "linux/amd64",
            "--network",
            "none",
            "--volume",
            sdk <> ":/sdk:ro",
            "--volume",
            tools <> ":/tools:ro",
            "--volume",
            workspace <> ":/work",
            profile["container_image"],
            "/tools/zap/zap-cli",
            "generate",
            "--tempState",
            "--skipPostGeneration",
            "--noLoadingFailure=false",
            "--noServer",
            "--noUi",
            "-z",
            "/sdk/src/app/zap-templates/zcl/zcl.json",
            "-g",
            "/sdk/src/app/zap-templates/" <> templates,
            "-i",
            "/work/bridge-app.zap",
            "-o",
            "/work/" <> directory
          ],
          timeout: 120_000
        )

      File.write!(Path.join(workspace, directory <> "-generation.log"), output, [:exclusive])
    end

    actual =
      Path.wildcard(Path.join([workspace, "{cpp,idl}", "**", "*"]))
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{Path.relative_to(&1, workspace), SoftwareManifest.digest(&1)})

    unless actual == profile["generated_sha256"], do: Mix.raise("bridge_model_generated_mismatch")
    :ok
  end

  @spec verify!(map()) :: :ok
  def verify!(model) do
    [root, aggregator, dummy] = model["endpointTypes"]
    unless ids(root) == @root_clusters, do: Mix.raise("bridge_model_root_clusters")
    unless ids(aggregator) == [0x001D], do: Mix.raise("bridge_model_aggregator_clusters")
    unless ids(dummy) == @dummy_clusters, do: Mix.raise("bridge_model_dummy_clusters")

    for cluster <- root["clusters"] ++ aggregator["clusters"] ++ dummy["clusters"] do
      revision = attribute(cluster, 0xFFFD)["defaultValue"]

      unless revision == Integer.to_string(@revisions[cluster["code"]]),
        do: Mix.raise("bridge_model_cluster_revision")
    end

    for cluster <- dummy["clusters"] do
      commands =
        cluster
        |> Map.get("commands", [])
        |> Enum.filter(&(&1["source"] == "client" and &1["isEnabled"] == 1))
        |> Enum.map(& &1["code"])
        |> Enum.sort()

      unless commands == @commands[cluster["code"]],
        do: Mix.raise("bridge_model_required_commands")

      included =
        cluster["attributes"]
        |> Enum.filter(&(&1["included"] == 1))
        |> Enum.map(& &1["code"])

      unless Enum.all?(@required_attributes[cluster["code"]], &(&1 in included)),
        do: Mix.raise("bridge_model_required_attributes")
    end

    on_off = Enum.find(dummy["clusters"], &(&1["code"] == 6))

    unless attribute(on_off, 0xFFFC)["defaultValue"] == "1",
      do: Mix.raise("bridge_model_lighting_feature")

    :ok
  end

  defp read_zap(sdk, path), do: SoftwareManifest.read(Path.join(sdk, path))

  defp select_clusters(clusters, ids) do
    clusters
    |> Enum.filter(&(&1["enabled"] == 1 and &1["side"] == "server" and &1["code"] in ids))
    |> Enum.map(&normalize_cluster(&1, &1["code"]))
  end

  defp normalize_cluster(cluster, id) do
    attributes =
      Enum.map(cluster["attributes"], fn attribute ->
        case attribute["code"] do
          0xFFFD -> Map.put(attribute, "defaultValue", Integer.to_string(@revisions[id]))
          0xFFFC when id == 6 -> Map.put(attribute, "defaultValue", "1")
          0xFFFC when id == 0x0062 -> Map.put(attribute, "defaultValue", "0")
          0 when id == 4 -> Map.put(attribute, "defaultValue", "0")
          3 when id == 0x0402 -> Map.put(attribute, "included", 0)
          _ -> attribute
        end
      end)

    Map.put(cluster, "attributes", attributes)
  end

  defp ids(endpoint) do
    endpoint["clusters"]
    |> Enum.map(& &1["code"])
    |> Enum.sort()
  end

  defp attribute(cluster, id), do: Enum.find(cluster["attributes"], &(&1["code"] == id))
end
