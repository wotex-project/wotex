defmodule Wotex.Workspace.NativeArtifact.VerifierTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.Archive
  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.PayloadManifest
  alias Wotex.Workspace.NativeArtifact.Verifier
  alias WotexWorkspace.Fixtures
  alias WotexWorkspace.NativeArtifactArchiveFixture, as: Tar

  @build_identity String.duplicate("a", 64)

  setup context do
    root = Fixtures.tmp_dir(context)
    payload = Path.join(root, "payload")
    File.mkdir_p!(Path.join(payload, "bin"))
    Fixtures.write!(payload, "bin/tool", "payload\n")
    File.chmod!(Path.join(payload, "bin/tool"), 0o755)
    descriptor = descriptor()

    assert {:ok, manifest} =
             PayloadManifest.build(descriptor, "linux-x86-64", @build_identity, payload)

    %{root: root, payload: payload, descriptor: descriptor, manifest: manifest}
  end

  test "verifies plain and compressed artifacts without mutating the payload", context do
    before_paths = paths(context.root)

    for {name, gzip?} <- [{"artifact.tar", false}, {"artifact.tar.gz", true}] do
      path = write_archive(context, name, context.manifest, [payload_entry()], gzip: gzip?)

      assert {:ok, result} =
               Verifier.verify(
                 path,
                 context.descriptor,
                 "linux-x86-64",
                 @build_identity
               )

      assert result.manifest.payload_identity == context.manifest.payload_identity
      assert result.transport_sha256 =~ ~r/^[0-9a-f]{64}$/
    end

    assert paths(context.root) -- before_paths == ["artifact.tar", "artifact.tar.gz"]
  end

  test "aggregates missing, extra, content, size and mode mismatches", context do
    archive =
      write_archive(context, "mismatch.tar", context.manifest, [
        %{payload_entry() | content: "changed"},
        %{path: "extra", kind: :file, content: "x", mode: 0o600}
      ])

    assert {:error, errors} =
             Verifier.verify(
               archive,
               context.descriptor,
               "linux-x86-64",
               @build_identity
             )

    assert Enum.any?(errors, &String.contains?(&1, "undeclared manifest entry extra"))
    assert Enum.any?(errors, &String.contains?(&1, "bin/tool size mismatch"))
    assert Enum.any?(errors, &String.contains?(&1, "bin/tool sha256 mismatch"))

    missing = write_archive(context, "missing.tar", context.manifest, [])

    assert {:error, errors} =
             Verifier.verify(
               missing,
               context.descriptor,
               "linux-x86-64",
               @build_identity
             )

    assert Enum.any?(errors, &String.contains?(&1, "missing manifest entry bin/tool"))

    wrong_mode =
      write_archive(context, "mode.tar", context.manifest, [%{payload_entry() | mode: 0o700}])

    assert {:error, errors} =
             Verifier.verify(
               wrong_mode,
               context.descriptor,
               "linux-x86-64",
               @build_identity
             )

    assert Enum.any?(errors, &String.contains?(&1, "bin/tool mode mismatch"))

    wrong_kind =
      write_archive(context, "kind.tar", context.manifest, [
        %{path: "bin/tool", kind: :directory, mode: 0o755}
      ])

    assert {:error, errors} =
             Verifier.verify(
               wrong_kind,
               context.descriptor,
               "linux-x86-64",
               @build_identity
             )

    assert Enum.any?(errors, &String.contains?(&1, "bin/tool kind mismatch"))
  end

  test "rejects descriptor, target and full build identity mismatches", context do
    archive = write_archive(context, "artifact.tar", context.manifest, [payload_entry()])

    assert {:error, errors} =
             Verifier.verify(
               archive,
               %{context.descriptor | package: "other"},
               "linux-x86-64",
               String.duplicate("b", 64)
             )

    assert Enum.any?(errors, &String.contains?(&1, "package mismatch"))
    assert Enum.any?(errors, &String.contains?(&1, "build identity mismatch"))

    unsupported = %{
      context.descriptor
      | targets: [%{name: "linux-x86-64", status: :unsupported, reason: "not qualified"}]
    }

    assert {:error, errors} =
             Verifier.verify(archive, unsupported, "linux-x86-64", @build_identity)

    assert Enum.any?(errors, &String.contains?(&1, "target is unsupported"))
  end

  test "rejects unknown manifest fields, schema majors and required extensions", context do
    base = PayloadManifest.to_map(context.manifest)

    cases = [
      {Map.put(base, "surprise", true), "unknown fields"},
      {%{base | "schema" => "wotex.native-payload-manifest@2"}, "manifest@1"},
      {%{base | "required" => ["future" | base["required"]]}, "unknown required fields"}
    ]

    for {map, expected} <- cases do
      archive =
        Tar.write!(
          Path.join(context.root, "#{System.unique_integer([:positive])}.tar"),
          [manifest_entry(JSON.encode!(map)), payload_entry()]
        )

      assert {:error, errors} =
               Verifier.verify(
                 archive,
                 context.descriptor,
                 "linux-x86-64",
                 @build_identity
               )

      assert Enum.any?(errors, &String.contains?(&1, expected))
    end
  end

  test "rejects descriptor-forbidden extra outputs even when the manifest names them", context do
    extra = %{
      "path" => "bin/extra",
      "kind" => "file",
      "mode" => 0o600,
      "size" => 1,
      "sha256" => sha256("x"),
      "link_target" => nil
    }

    entries = Enum.sort_by([extra | context.manifest.entries], & &1["path"])
    assert {:ok, payload_identity} = PayloadManifest.payload_identity(entries)
    manifest = %{context.manifest | entries: entries, payload_identity: payload_identity}

    archive =
      write_archive(context, "extra-declared.tar", manifest, [
        payload_entry(),
        %{path: "bin/extra", kind: :file, content: "x", mode: 0o600}
      ])

    assert {:error, errors} =
             Verifier.verify(
               archive,
               context.descriptor,
               "linux-x86-64",
               @build_identity
             )

    assert Enum.any?(errors, &String.contains?(&1, "undeclared output bin/extra"))
  end

  defp write_archive(context, name, manifest, entries, opts \\ []) do
    assert {:ok, bytes} = PayloadManifest.encode(manifest)

    Tar.write!(
      Path.join(context.root, name),
      [manifest_entry(bytes) | entries],
      opts
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
          %{"path" => "bin/tool", "kind" => "file", "mode" => 0o755, "required" => true}
        ]
      }
    }
  end

  defp manifest_entry(bytes),
    do: %{path: Archive.manifest_path(), kind: :file, content: bytes, mode: 0o644}

  defp payload_entry,
    do: %{path: "bin/tool", kind: :file, content: "payload\n", mode: 0o755}

  defp paths(root) do
    root
    |> File.ls!()
    |> Enum.sort()
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
