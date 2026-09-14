defmodule Wotex.Matter.SoftwarePeerExtension do
  @moduledoc false

  alias Wotex.Matter.SoftwareManifest

  @sources [
    {"examples/all-clusters-app/linux/AllClustersCommandDelegate.cpp",
     "d2d905dabd9cff07d0680cdda1c8b91ec0f063b162d889fd8c7b17f271c45ec5", "all_clusters_control.inc",
     "    if (name == \"SoftwareFault\")\n"},
    {"examples/bridge-app/linux/main.cpp",
     "166198160a663e4bef32400cdbdc9554f12ff381e02e8f485c6a7bba6eb5e3d0", "bridge_control.inc",
     "    if (name == \"SimulateConfigurationVersionChange\")\n"}
  ]

  @spec apply!(String.t(), String.t()) :: [map()]
  def apply!(root, sdk) do
    prepared =
      Enum.map(@sources, fn {relative, digest, fragment, anchor} ->
        path = Path.join(sdk, relative)

        unless SoftwareManifest.digest(path) == digest,
          do: Mix.raise("peer_extension_source_mismatch")

        fragment_path = "test/support/software/" <> fragment
        extension = File.read!(Path.join(root, fragment_path))
        source = File.read!(path)
        unless length(:binary.matches(source, anchor)) == 1, do: Mix.raise("peer_extension_anchor")
        patched = String.replace(source, anchor, extension, global: false)

        patched =
          if fragment == "all_clusters_control.inc" do
            String.replace(
              patched,
              "#include <app/server/Server.h>",
              "#include <app/server/Server.h>\n" <>
                "#include <app/clusters/temperature-measurement-server/CodegenIntegration.h>",
              global: false
            )
          else
            patched
          end

        record = %{
          "upstream_path" => relative,
          "upstream_sha256" => digest,
          "extension_path" => fragment_path,
          "extension_sha256" => SoftwareManifest.digest(Path.join(root, fragment_path)),
          "patched_sha256" => :crypto.hash(:sha256, patched) |> Base.encode16(case: :lower)
        }

        {path, patched, record}
      end)

    Enum.map(prepared, fn {path, patched, record} ->
      File.write!(path, patched)
      record
    end)
  end
end
