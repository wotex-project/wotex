defmodule Wotex.Workspace.NativeArtifact.InventoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Inventory
  alias WotexWorkspace.Fixtures

  setup context do
    root = Fixtures.tmp_dir(context)
    %{root: root}
  end

  test "loads only explicitly admitted descriptor paths without package code", %{root: root} do
    manifest = manifest()

    Fixtures.write!(
      root,
      "packages/native/priv/native-artifacts/production.json",
      JSON.encode!(descriptor())
    )

    Fixtures.write!(
      root,
      "packages/native/priv/native-artifacts/unadmitted.json",
      JSON.encode!(%{descriptor() | "profile" => "unadmitted"})
    )

    Fixtures.write!(root, "packages/native/lib/native.ex", "raise \"must not load package code\"\n")

    assert {:ok, [loaded]} = Inventory.load(manifest, root)
    assert loaded.profile == "production"
    assert loaded.path == "packages/native/priv/native-artifacts/production.json"
  end

  test "reports every missing or mismatched admitted descriptor", %{root: root} do
    manifest =
      manifest([
        %{"profile" => "production", "descriptor" => "priv/native-artifacts/production.json"},
        %{"profile" => "sanitizers", "descriptor" => "priv/native-artifacts/sanitizers.json"}
      ])

    Fixtures.write!(
      root,
      "packages/native/priv/native-artifacts/production.json",
      JSON.encode!(%{descriptor() | "package" => "other"})
    )

    assert {:error, errors} = Inventory.load(manifest, root)
    assert length(errors) == 2
    assert Enum.any?(errors, &String.contains?(&1, "expected \"native\""))
    assert Enum.any?(errors, &String.contains?(&1, "enoent"))
  end

  test "reports malformed JSON without raising", %{root: root} do
    manifest = manifest()

    Fixtures.write!(
      root,
      "packages/native/priv/native-artifacts/production.json",
      ~S({"schema":)
    )

    assert {:error, [message]} = Inventory.load(manifest, root)
    assert message =~ "invalid JSON"
    assert message =~ "production.json"
  end

  defp manifest(
         profiles \\ [
           %{"profile" => "production", "descriptor" => "priv/native-artifacts/production.json"}
         ]
       ) do
    {:ok, manifest} =
      Manifest.from_map(%{
        "packages" => %{
          "native" => %{
            "app" => "native",
            "native" => true,
            "native_artifacts" => profiles
          }
        },
        "native_artifact" => %{
          "schema_version" => "1.0.0",
          "toolchains" => %{"compiler" => %{"identity" => "compiler-v1"}},
          "systems" => %{"host" => %{"identity" => "host-v1"}},
          "targets" => %{
            "linux" => %{
              "operating_system" => "linux",
              "architecture" => "x86_64",
              "endianness" => "little",
              "libc" => "glibc",
              "abi" => "gnu",
              "toolchain" => "compiler",
              "system" => "host"
            }
          }
        }
      })

    manifest
  end

  defp descriptor do
    %{
      "schema" => "wotex.native-artifact-descriptor@2",
      "artifact_format" => "wotex.native-artifact@1",
      "package" => "native",
      "profile" => "production",
      "kind" => "executable",
      "targets" => [%{"name" => "linux", "status" => "supported"}],
      "sources" => %{"first_party" => ["src"], "upstream" => []},
      "patches" => [],
      "toolchain" => %{"inputs" => [], "requirements" => %{}, "container_digest" => nil},
      "build" => %{"task" => "native.build", "options" => %{}, "features" => []},
      "qualification" => %{"task" => "native.test", "options" => %{}, "features" => []},
      "outputs" => [%{"path" => "bin/native", "kind" => "file", "mode" => 493, "required" => true}],
      "compatibility" => %{},
      "external_libraries" => [],
      "legal" => ["LICENSE"],
      "native_inputs" => [],
      "retrieval" => %{"sources" => []}
    }
  end
end
