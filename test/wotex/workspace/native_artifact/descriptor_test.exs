defmodule Wotex.Workspace.NativeArtifact.DescriptorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.Descriptor

  defp manifest do
    {:ok, manifest} =
      Manifest.from_map(%{
        "packages" => %{
          "native" => %{
            "app" => "native",
            "native" => true,
            "native_artifacts" => [
              %{"profile" => "production", "descriptor" => "priv/native-artifacts/production.json"}
            ]
          }
        },
        "native_artifact" => %{
          "schema_version" => "1.0.0",
          "toolchains" => %{"toolchain" => %{"identity" => "toolchain-v1"}},
          "systems" => %{"host" => %{"identity" => "host-v1"}},
          "targets" => %{
            "linux-x86-64" => %{
              "operating_system" => "linux",
              "architecture" => "x86_64",
              "endianness" => "little",
              "libc" => "glibc",
              "abi" => "gnu",
              "toolchain" => "toolchain",
              "system" => "host"
            }
          }
        }
      })

    manifest
  end

  defp valid do
    %{
      "schema" => "wotex.native-artifact-descriptor@2",
      "artifact_format" => "wotex.native-artifact@1",
      "package" => "native",
      "profile" => "production",
      "kind" => "executable",
      "targets" => [%{"name" => "linux-x86-64", "status" => "supported"}],
      "sources" => %{
        "first_party" => ["native"],
        "upstream" => [
          %{
            "name" => "sdk",
            "url" => "https://example.invalid/sdk/0123456789012345678901234567890123456789",
            "revision" => "0123456789012345678901234567890123456789",
            "sha256" => String.duplicate("a", 64)
          }
        ]
      },
      "patches" => [],
      "toolchain" => %{"inputs" => [], "requirements" => %{"c" => "c11"}, "container_digest" => nil},
      "build" => %{"task" => "native.build", "options" => %{}, "features" => ["one"]},
      "qualification" => %{"task" => "native.test", "options" => %{}, "features" => []},
      "outputs" => [%{"path" => "bin/native", "kind" => "file", "mode" => 493, "required" => true}],
      "compatibility" => %{"abi" => "v1"},
      "external_libraries" => [],
      "legal" => ["LICENSE"],
      "native_inputs" => [],
      "retrieval" => %{
        "sources" => [
          %{
            "name" => "hosted",
            "url" =>
              "https://artifacts.example.invalid/{package}/{profile}/{target}/{build_identity}.tar.gz"
          }
        ]
      }
    }
  end

  test "accepts the closed schema and preserves an explicit unsupported target" do
    map =
      update_in(valid()["targets"], fn targets ->
        [
          %{
            "name" => "linux-x86-64",
            "status" => "unsupported",
            "reason" => "contradiction"
          }
          | targets
        ]
      end)

    assert {:error, message} = Descriptor.from_map(map, manifest())
    assert message =~ "duplicate or contradictory"

    map =
      put_in(valid()["targets"], [
        %{
          "name" => "linux-x86-64",
          "status" => "unsupported",
          "reason" => "qualification-only target is unavailable"
        }
      ])

    assert {:ok, descriptor} = Descriptor.from_map(map, manifest())

    assert {:ok, %{status: :unsupported, reason: reason}} =
             Descriptor.target(descriptor, "linux-x86-64")

    assert reason =~ "unavailable"
  end

  test "rejects unknown versions, missing and unknown fields, invalid types and undeclared targets" do
    assert {:error, message} =
             Descriptor.from_map(
               %{valid() | "schema" => "wotex.native-artifact-descriptor@3"},
               manifest()
             )

    assert message =~ "expected \"wotex.native-artifact-descriptor@2\""

    assert {:error, message} = Descriptor.from_map(Map.delete(valid(), "outputs"), manifest())
    assert message =~ "missing required fields: outputs"

    assert {:error, message} = Descriptor.from_map(Map.put(valid(), "surprise", true), manifest())
    assert message =~ "unknown fields: surprise"

    assert {:error, message} = Descriptor.from_map(put_in(valid()["outputs"], "bad"), manifest())
    assert message =~ "outputs"

    map = put_in(valid()["targets"], [%{"name" => "other", "status" => "supported"}])
    assert {:error, message} = Descriptor.from_map(map, manifest())
    assert message =~ "undeclared target"
  end

  test "rejects credentials, cache paths, absolute paths, mutable revisions and short digests" do
    for {map, expected} <- [
          {put_in(valid(), ["build", "options"], %{"password" => "x"}),
           "forbidden descriptor field"},
          {put_in(valid(), ["build", "options"], %{"cache_path" => "cache"}),
           "forbidden descriptor field"},
          {put_in(valid()["legal"], ["/tmp/LICENSE"]), "absolute paths"},
          {put_in(valid(), ["sources", "upstream", Access.at(0), "revision"], "main"),
           "mutable or invalid"},
          {put_in(valid(), ["sources", "upstream", Access.at(0), "sha256"], "abcd"),
           "full lowercase SHA-256"},
          {put_in(valid()["compatibility"], %{"ratio" => 1.0}), "floating-point"}
        ] do
      assert {:error, message} = Descriptor.from_map(map, manifest())
      assert message =~ expected
    end
  end

  test "sorts only declared unordered collections and retains patch order" do
    patches = [
      %{"id" => "second", "path" => "patches/2.patch", "sha256" => String.duplicate("2", 64)},
      %{"id" => "first", "path" => "patches/1.patch", "sha256" => String.duplicate("1", 64)}
    ]

    map =
      valid()
      |> put_in(["patches"], patches)
      |> put_in(["build", "features"], ["z", "a"])

    assert {:ok, descriptor} = Descriptor.from_map(map, manifest())
    assert Enum.map(descriptor.raw["patches"], & &1["id"]) == ["second", "first"]
    assert descriptor.raw["build"]["features"] == ["a", "z"]
  end

  test "admits only bounded immutable credential-free retrieval templates" do
    source = hd(valid()["retrieval"]["sources"])

    for {url, expected} <- [
          {"https://artifacts.example.invalid/latest.tar.gz", "include {build_identity}"},
          {"https://artifacts.example.invalid/{unknown}/{build_identity}.tar.gz",
           "unknown template"},
          {"http://artifacts.example.invalid/{build_identity}.tar.gz", "HTTPS URL"},
          {"https://user:secret@artifacts.example.invalid/{build_identity}.tar.gz", "credentials"},
          {"https://artifacts.example.invalid/{build_identity}.tar.gz?token=value", "query strings"}
        ] do
      map = put_in(valid(), ["retrieval", "sources"], [%{source | "url" => url}])
      assert {:error, message} = Descriptor.from_map(map, manifest())
      assert message =~ expected
    end

    duplicate = [source, source]

    assert {:error, message} =
             Descriptor.from_map(put_in(valid(), ["retrieval", "sources"], duplicate), manifest())

    assert message =~ "duplicate source names"
  end
end
