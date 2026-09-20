defmodule Wotex.Workspace.NativeArtifact.IdentityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeArtifact.CanonicalJSON
  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.Identity
  alias WotexWorkspace.Fixtures

  setup context do
    root = Fixtures.tmp_dir(context)
    Fixtures.write!(root, "packages/native/src/main.c", "int main(void) { return 0; }\n")
    patch = Fixtures.write!(root, "packages/native/patches/one.patch", "patch one\n")
    Fixtures.write!(root, "packages/native/toolchain.lock", "package tool\n")
    Fixtures.write!(root, "tooling/compiler.lock", "compiler\n")
    Fixtures.write!(root, "systems/rootfs.lock", "rootfs\n")

    manifest = manifest()
    map = descriptor_map(Identity.sha256(File.read!(patch)))
    assert {:ok, descriptor} = Descriptor.from_map(map, manifest, "descriptor.json")
    %{root: root, manifest: manifest, descriptor: descriptor}
  end

  test "uses a full deterministic digest and ignores map insertion order", context do
    assert {:ok, first} = build(context)
    assert first.identity =~ ~r/^[0-9a-f]{64}$/

    reordered =
      context.descriptor.raw
      |> Enum.reverse()
      |> Map.new()

    assert {:ok, second} = build(%{context | descriptor: %{context.descriptor | raw: reordered}})
    assert second.identity == first.identity
    assert second.canonical == first.canonical
  end

  test "every descriptor field independently moves identity", context do
    assert {:ok, baseline} = build(context)
    raw = context.descriptor.raw

    mutations = %{
      "schema" => &Map.put(&1, "schema", "wotex.native-artifact-descriptor@9"),
      "artifact_format" => &Map.put(&1, "artifact_format", "wotex.native-artifact@9"),
      "package" => &Map.put(&1, "package", "native-other"),
      "profile" => &Map.put(&1, "profile", "debug"),
      "kind" => &Map.put(&1, "kind", "shared-library"),
      "targets" => &put_in(&1, ["targets", Access.at(0), "extra"], "semantic"),
      "sources" =>
        &put_in(&1, ["sources", "upstream", Access.at(0), "revision"], String.duplicate("2", 40)),
      "patches" => &put_in(&1, ["patches", Access.at(0), "id"], "renamed-patch"),
      "toolchain" => &put_in(&1, ["toolchain", "requirements", "c"], "c17"),
      "build" => &put_in(&1, ["build", "options", "optimization"], "debug"),
      "qualification" => &put_in(&1, ["qualification", "features"], ["asan"]),
      "outputs" => &put_in(&1, ["outputs", Access.at(0), "mode"], 420),
      "compatibility" => &put_in(&1, ["compatibility", "abi"], "v2"),
      "external_libraries" => &Map.put(&1, "external_libraries", ["libm.so.6"]),
      "legal" => &Map.put(&1, "legal", ["LICENSE", "NOTICE"]),
      "native_inputs" =>
        &Map.put(&1, "native_inputs", [
          %{"name" => "dependency", "build_identity" => String.duplicate("d", 64)}
        ])
    }

    for {field, mutate} <- mutations do
      descriptor = %{context.descriptor | raw: mutate.(raw)}
      assert {:ok, changed} = build(%{context | descriptor: descriptor}), field
      refute changed.identity == baseline.identity, field
    end
  end

  test "repository, source, toolchain and system content independently move identity", context do
    assert {:ok, baseline} = build(context)

    assert {:ok, revision} =
             Identity.build(
               context.descriptor,
               "linux-x86-64",
               String.duplicate("b", 40),
               context.manifest,
               context.root
             )

    refute revision.identity == baseline.identity

    for path <- [
          "packages/native/src/main.c",
          "packages/native/toolchain.lock",
          "tooling/compiler.lock",
          "systems/rootfs.lock"
        ] do
      original = File.read!(Path.join(context.root, path))
      File.write!(Path.join(context.root, path), original <> "changed\n")
      assert {:ok, changed} = build(context), path
      refute changed.identity == baseline.identity, path
      File.write!(Path.join(context.root, path), original)
    end
  end

  test "verifies ordered patch content and refuses unsupported targets", context do
    File.write!(Path.join(context.root, "packages/native/patches/one.patch"), "changed\n")
    assert {:error, message} = build(context)
    assert message =~ "patch digest mismatch"

    descriptor = %{
      context.descriptor
      | targets: [%{name: "linux-x86-64", status: :unsupported, reason: "not qualified"}]
    }

    assert {:error, "target linux-x86-64 is unsupported: not qualified"} =
             Identity.build(
               descriptor,
               "linux-x86-64",
               String.duplicate("a", 40),
               context.manifest,
               context.root
             )
  end

  test "absence and an empty value are distinct canonical inputs" do
    refute CanonicalJSON.encode!(%{"a" => []}) == CanonicalJSON.encode!(%{})
  end

  defp build(context) do
    Identity.build(
      context.descriptor,
      "linux-x86-64",
      String.duplicate("a", 40),
      context.manifest,
      context.root
    )
  end

  defp manifest do
    {:ok, manifest} =
      Manifest.from_map(%{
        "packages" => %{
          "native" => %{
            "app" => "native",
            "native" => true,
            "native_artifacts" => [
              %{"profile" => "production", "descriptor" => "descriptor.json"}
            ]
          }
        },
        "native_artifact" => %{
          "schema_version" => "1.0.0",
          "toolchains" => %{
            "toolchain" => %{
              "identity" => "compiler-v1",
              "inputs" => ["tooling/compiler.lock"]
            }
          },
          "systems" => %{
            "host" => %{"identity" => "rootfs-v1", "inputs" => ["systems/rootfs.lock"]}
          },
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

  defp descriptor_map(patch_digest) do
    %{
      "schema" => "wotex.native-artifact-descriptor@1",
      "artifact_format" => "wotex.native-artifact@1",
      "package" => "native",
      "profile" => "production",
      "kind" => "executable",
      "targets" => [%{"name" => "linux-x86-64", "status" => "supported"}],
      "sources" => %{
        "first_party" => ["src"],
        "upstream" => [
          %{
            "name" => "sdk",
            "url" => "https://example.invalid/sdk/1111111111111111111111111111111111111111",
            "revision" => String.duplicate("1", 40),
            "sha256" => String.duplicate("c", 64)
          }
        ]
      },
      "patches" => [
        %{"id" => "one", "path" => "patches/one.patch", "sha256" => patch_digest}
      ],
      "toolchain" => %{
        "inputs" => ["toolchain.lock"],
        "requirements" => %{"c" => "c11"},
        "container_digest" => nil
      },
      "build" => %{"task" => "native.build", "options" => %{}, "features" => []},
      "qualification" => %{"task" => "native.test", "options" => %{}, "features" => []},
      "outputs" => [
        %{"path" => "bin/native", "kind" => "file", "mode" => 493, "required" => true}
      ],
      "compatibility" => %{"abi" => "v1"},
      "external_libraries" => [],
      "legal" => ["LICENSE"],
      "native_inputs" => []
    }
  end
end
