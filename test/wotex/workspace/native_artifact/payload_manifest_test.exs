defmodule Wotex.Workspace.NativeArtifact.PayloadManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.PayloadManifest
  alias WotexWorkspace.Fixtures

  setup context do
    root = Fixtures.tmp_dir(context)
    File.mkdir_p!(Path.join(root, "bin"))
    File.chmod!(Path.join(root, "bin"), 0o755)
    Fixtures.write!(root, "bin/tool", "payload\n")
    File.chmod!(Path.join(root, "bin/tool"), 0o755)
    %{root: root, descriptor: descriptor()}
  end

  test "builds deterministic entries and an independent full payload identity", context do
    assert {:ok, first} = build(context)
    assert first.payload_identity =~ ~r/^[0-9a-f]{64}$/
    assert Enum.map(first.entries, & &1["path"]) == ["bin", "bin/tool"]

    assert {:ok, encoded} = PayloadManifest.encode(first)
    assert {:ok, decoded} = PayloadManifest.decode(encoded)
    assert decoded == first

    File.touch!(Path.join(context.root, "bin/tool"), 1_700_000_000)
    assert {:ok, same} = build(context)
    assert same.payload_identity == first.payload_identity

    File.write!(Path.join(context.root, "bin/tool"), "changed\n")
    assert {:ok, changed} = build(context)
    refute changed.payload_identity == first.payload_identity
  end

  test "rejects special outputs and escaping links", context do
    File.rm!(Path.join(context.root, "bin/tool"))
    File.ln_s!("../../outside", Path.join(context.root, "bin/tool"))

    assert {:error, message} = build(context)
    assert message =~ "escapes the artifact root"
  end

  test "enforces declared root kind and mode while permitting an absent optional output", context do
    File.chmod!(Path.join(context.root, "bin"), 0o700)
    assert {:error, message} = build(context)
    assert message =~ "expected mode"

    optional = %{
      context.descriptor
      | raw: %{
          "outputs" => [
            %{
              "path" => "missing",
              "kind" => "file",
              "mode" => 0o600,
              "required" => false
            }
          ]
        }
    }

    assert {:ok, manifest} =
             PayloadManifest.build(
               optional,
               "linux-x86-64",
               String.duplicate("a", 64),
               context.root
             )

    assert manifest.entries == []
  end

  test "rejects unknown versions, required fields, identity mismatch and deep manifests", context do
    assert {:ok, manifest} = build(context)
    map = PayloadManifest.to_map(manifest)

    assert {:error, message} =
             PayloadManifest.from_map(%{map | "schema" => "wotex.native-payload-manifest@2"})

    assert message =~ "expected \"wotex.native-payload-manifest@1\""

    assert {:error, message} =
             PayloadManifest.from_map(%{map | "required" => ["future" | map["required"]]})

    assert message =~ "unknown required fields"

    assert {:error, message} =
             PayloadManifest.from_map(%{map | "payload_identity" => String.duplicate("0", 64)})

    assert message =~ "computed"

    deep = Enum.reduce(1..40, %{}, fn index, value -> %{"#{index}" => value} end)
    deep_map = %{map | "optional" => deep}
    bytes = JSON.encode!(deep_map)
    assert {:error, message} = PayloadManifest.decode(bytes, max_depth: 16)
    assert message =~ "nesting depth"
  end

  test "bounds manifest bytes and values", context do
    assert {:ok, manifest} = build(context)
    assert {:ok, bytes} = PayloadManifest.encode(manifest)

    assert {:error, message} = PayloadManifest.decode(bytes, max_bytes: byte_size(bytes) - 1)
    assert message =~ "exceeds"

    assert {:error, message} = PayloadManifest.decode(bytes, max_nodes: 2)
    assert message =~ "values"
  end

  defp build(context) do
    PayloadManifest.build(
      context.descriptor,
      "linux-x86-64",
      String.duplicate("a", 64),
      context.root
    )
  end

  defp descriptor do
    %Descriptor{
      package: "native",
      profile: "production",
      kind: "executable",
      targets: [%{name: "linux-x86-64", status: :supported, reason: nil}],
      raw: %{
        "outputs" => [
          %{"path" => "bin", "kind" => "directory", "mode" => 0o755, "required" => true}
        ]
      }
    }
  end
end
