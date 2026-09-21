Code.require_file("../../../bin/support/distribution.exs", __DIR__)

defmodule Wotex.Lab.DistributionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Check.Distribution

  @revision String.duplicate("a", 40)
  @source_digest "sha256:" <> String.duplicate("b", 64)

  @tag :tmp_dir
  test "the manifest binds sorted relative paths, sizes and bytes", %{tmp_dir: root} do
    put_file(root, "source/host.tar", "host")
    put_file(root, "hex/wotex-0.1.0.tar", "package")

    assert {:ok, manifest} = Distribution.build_manifest(root, @revision, @source_digest)
    assert manifest["schema_version"] == "wotex-lab-distribution/v1"

    assert Enum.map(manifest["artifacts"], & &1["path"]) ==
             ~w(hex/wotex-0.1.0.tar source/host.tar)

    assert :ok = Distribution.validate_manifest(manifest, root)
    assert {:ok, encoded} = Distribution.encode(manifest)
    assert {:ok, ^manifest} = Wotex.JSON.decode(encoded)

    put_file(root, "source/host.tar", "changed")
    assert {:error, :invalid_distribution} = Distribution.validate_manifest(manifest, root)
  end

  @tag :tmp_dir
  test "empty, forged, duplicated and escaping manifests fail closed", %{tmp_dir: root} do
    assert {:error, :invalid_distribution} =
             Distribution.build_manifest(root, @revision, @source_digest)

    put_file(root, "artifact", "ok")
    assert {:ok, manifest} = Distribution.build_manifest(root, @revision, @source_digest)
    [artifact] = manifest["artifacts"]

    for changed <- [
          Map.put(manifest, "unknown", true),
          Map.put(manifest, "revision", "main"),
          Map.put(manifest, "source_digest", "sha256:no"),
          Map.put(manifest, "artifacts", []),
          Map.put(manifest, "artifacts", [artifact, artifact]),
          Map.put(manifest, "artifacts", [%{artifact | "path" => "../artifact"}]),
          Map.put(manifest, "artifacts", [%{artifact | "bytes" => 0}]),
          Map.put(manifest, "artifacts", [%{artifact | "digest" => @source_digest}])
        ] do
      assert {:error, :invalid_distribution} = Distribution.validate_manifest(changed, root)
    end
  end

  test "candidate layouts are closed and release artifacts are atomic" do
    hex =
      ~w(wotex wotex_runtime wotex_binding_http wotex_binding_mqtt
         wotex_modbus wotex_coap wotex_bacnet wotex_opcua wotex_ble
         wotex_matter wotex_thread wotex_directory wotex_continuum
         wotex_nx wotex_conformance wotex_lab)
      |> Enum.map(&"hex/#{&1}-0.1.0.tar")

    base =
      hex ++
        ~w(source/wotex-lab-workbench.tar source/wotex-lab-oci-context.tar
           source/wotex-lab-nerves-rpi4.tar npm/wotex-lab-client-0.1.0.tgz)

    assert :ok = Distribution.validate_candidate_paths(base, false)
    assert {:error, :invalid_candidate_layout} = Distribution.validate_candidate_paths(base, true)

    release =
      base ++
        ~w(release/wotex-lab-workbench-aarch64-apple-darwin.tar.gz
           release/wotex-lab-workbench-source.tar
           static/wotex-lab-documentation.tar.gz)

    assert :ok = Distribution.validate_candidate_paths(release, false)
    assert :ok = Distribution.validate_candidate_paths(release, true)

    for changed <- [
          ["unknown" | base],
          [hd(base) | base],
          List.delete(base, hd(base)),
          ["release/wotex-lab-workbench-source.tar" | base],
          ["release/wotex-lab-workbench-aarch64-apple-darwin.tar.gz" | base],
          release -- ["static/wotex-lab-documentation.tar.gz"]
        ] do
      assert {:error, :invalid_candidate_layout} =
               Distribution.validate_candidate_paths(changed, false)
    end
  end

  defp put_file(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
