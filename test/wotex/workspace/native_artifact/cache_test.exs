defmodule Wotex.Workspace.NativeArtifact.CacheTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.NativeArtifact.Archive
  alias Wotex.Workspace.NativeArtifact.Cache
  alias Wotex.Workspace.NativeArtifact.Descriptor
  alias Wotex.Workspace.NativeArtifact.Lease
  alias Wotex.Workspace.NativeArtifact.PayloadManifest
  alias WotexWorkspace.Fixtures
  alias WotexWorkspace.NativeArtifactArchiveFixture, as: Tar

  @identity String.duplicate("a", 64)

  setup context do
    root = Fixtures.tmp_dir(context)
    payload = Path.join(root, "payload")
    cache = Path.join(root, "cache")
    File.mkdir_p!(Path.join(payload, "bin"))
    Fixtures.write!(payload, "bin/tool", "payload\n")
    File.chmod!(Path.join(payload, "bin/tool"), 0o755)

    %{
      root: root,
      payload: payload,
      cache: cache,
      descriptor: descriptor()
    }
  end

  test "adopts once under the full identity and reuses only a valid entry", context do
    artifact = write_artifact(context, @identity, "artifact.tar.gz", gzip: true)

    assert {:ok, fresh} = adopt(context, artifact, @identity)
    refute fresh.reused
    assert Path.basename(fresh.path) == @identity
    assert File.read!(Path.join([fresh.path, "payload", "bin", "tool"])) == "payload\n"

    assert {:ok, inspected} = inspect_cache(context, @identity)
    refute inspected.reused
    assert inspected.manifest.payload_identity == fresh.manifest.payload_identity

    assert {:ok, reused} = adopt(context, artifact, @identity)
    assert reused.reused
    assert reused.path == fresh.path
  end

  test "rejects corrupt metadata, payload and cached transport", context do
    artifact = write_artifact(context, @identity, "artifact.tar")
    assert {:ok, entry} = adopt(context, artifact, @identity)

    File.write!(Path.join(entry.path, "cache-entry.json"), "{}")
    assert {:error, errors} = inspect_cache(context, @identity)
    assert Enum.any?(errors, &String.contains?(&1, "closed schema"))

    File.cp!(artifact, Path.join(entry.path, "cache-entry.json"))
    assert {:error, errors} = inspect_cache(context, @identity)
    assert Enum.any?(errors, &String.contains?(&1, "invalid cache metadata JSON"))
  end

  test "does not follow cache metadata or payload-manifest symlinks", context do
    artifact = write_artifact(context, @identity, "artifact.tar")
    assert {:ok, entry} = adopt(context, artifact, @identity)

    metadata = Path.join(entry.path, "cache-entry.json")
    saved_metadata = Path.join(context.root, "saved-metadata.json")
    File.cp!(metadata, saved_metadata)
    File.rm!(metadata)
    File.ln_s!(saved_metadata, metadata)

    assert {:error, errors} = inspect_cache(context, @identity)
    assert Enum.any?(errors, &String.contains?(&1, "cache metadata is symlink"))

    File.rm!(metadata)
    File.cp!(saved_metadata, metadata)
    manifest = Path.join([entry.path, "payload", Archive.manifest_path()])
    saved_manifest = Path.join(context.root, "saved-manifest.json")
    File.cp!(manifest, saved_manifest)
    File.rm!(manifest)
    File.ln_s!(saved_manifest, manifest)

    assert {:error, errors} = inspect_cache(context, @identity)
    assert Enum.any?(errors, &String.contains?(&1, "payload manifest is symlink"))
  end

  test "detects payload and transport changes after adoption", context do
    artifact = write_artifact(context, @identity, "artifact.tar")
    assert {:ok, entry} = adopt(context, artifact, @identity)

    tool = Path.join([entry.path, "payload", "bin", "tool"])
    File.write!(tool, "changed\n")
    assert {:error, errors} = inspect_cache(context, @identity)
    assert Enum.any?(errors, &String.contains?(&1, "bin/tool sha256 mismatch"))

    File.write!(tool, "payload\n")
    File.write!(Path.join(entry.path, "artifact.tar"), "changed")
    assert {:error, errors} = inspect_cache(context, @identity)
    assert Enum.any?(errors, &String.contains?(&1, "cached archive size mismatch"))
  end

  test "preserves a prior valid entry when replacement input fails verification", context do
    artifact = write_artifact(context, @identity, "artifact.tar")
    assert {:ok, original} = adopt(context, artifact, @identity)

    broken = Path.join(context.root, "broken.tar")
    File.write!(broken, "not an artifact")
    assert {:error, _} = adopt(context, broken, @identity)

    assert {:ok, retained} = inspect_cache(context, @identity)
    assert retained.manifest.payload_identity == original.manifest.payload_identity
  end

  test "concurrent builders converge on one verified entry", context do
    artifact = write_artifact(context, @identity, "artifact.tar")

    tasks =
      for _ <- 1..2 do
        Task.async(fn -> adopt(context, artifact, @identity) end)
      end

    results = Enum.map(tasks, &Task.await(&1, 5_000))
    assert Enum.all?(results, &match?({:ok, _}, &1))

    reused = Enum.map(results, fn {:ok, entry} -> entry.reused end)
    assert Enum.sort(reused) == [false, true]

    assert {:ok, _} = inspect_cache(context, @identity)
    assert stage_names(context.cache) == []
  end

  @tag timeout: 10_000
  test "an adoption that outlives its lease cannot install", context do
    large = :binary.copy("0123456789abcdef", 2_097_152)
    File.write!(Path.join([context.payload, "bin", "tool"]), large)
    File.chmod!(Path.join([context.payload, "bin", "tool"]), 0o755)
    artifact = write_artifact(context, @identity, "large.tar")

    assert {:error, errors} =
             Cache.adopt(
               artifact,
               context.descriptor,
               "linux-x86-64",
               @identity,
               context.cache,
               lease_ttl_ms: 1
             )

    assert Enum.any?(errors, &String.contains?(&1, "lease expired or was lost"))
    refute File.exists?(entry_path(context.cache, @identity))
    assert stage_names(context.cache) == []
  end

  test "exact deletion respects active leases", context do
    artifact = write_artifact(context, @identity, "artifact.tar")
    assert {:ok, _} = adopt(context, artifact, @identity)
    assert {:ok, lease} = Lease.acquire(context.cache, @identity, ttl_ms: 1_000)

    assert {:error, message} = Cache.delete(context.cache, @identity, lease_wait_ms: 5)
    assert message =~ "timed out waiting"
    assert File.dir?(entry_path(context.cache, @identity))
    assert :ok = Lease.release(lease)
    assert :ok = Cache.delete(context.cache, @identity)
    refute File.exists?(entry_path(context.cache, @identity))

    assert {:error, message} = Cache.delete(context.cache, "abc")
    assert message =~ "full lowercase SHA-256"
  end

  test "garbage collection is bounded and never follows an unowned symlink", context do
    identities = Enum.map(~w(a b c), &String.duplicate(&1, 64))

    for {identity, index} <- Enum.with_index(identities) do
      artifact = write_artifact(context, identity, "artifact-#{index}.tar")
      assert {:ok, _} = adopt(context, artifact, identity)
    end

    corrupt_identity = String.duplicate("0", 64)
    corrupt = entry_path(context.cache, corrupt_identity)
    outside = Path.join(context.root, "outside")
    File.mkdir_p!(corrupt)
    File.mkdir_p!(outside)
    Fixtures.write!(outside, "retained", "safe")
    File.ln_s!(outside, Path.join(corrupt, "escape"))
    File.write!(Path.join(corrupt, "cache-entry.json"), "{}")

    assert {:ok, result} =
             Cache.garbage_collect(context.cache, max_scan: 2, max_remove: 1)

    assert result.scanned == 2
    assert result.removed == [hd(identities)]
    assert result.skipped == [corrupt_identity]
    assert File.read!(Path.join(outside, "retained")) == "safe"
    assert File.dir?(entry_path(context.cache, Enum.at(identities, 1)))
    assert File.dir?(entry_path(context.cache, Enum.at(identities, 2)))
  end

  test "refuses symlink cache roots", context do
    linked = Path.join(context.root, "linked-cache")
    File.mkdir_p!(context.cache)
    File.ln_s!(context.cache, linked)
    artifact = write_artifact(context, @identity, "artifact.tar")

    assert {:error, errors} =
             Cache.adopt(
               artifact,
               context.descriptor,
               "linux-x86-64",
               @identity,
               linked
             )

    assert Enum.any?(errors, &String.contains?(&1, "cache root is symlink"))
  end

  test "refuses a symlinked cache objects directory", context do
    objects = Path.join(context.cache, "objects")
    outside = Path.join(context.root, "outside-objects")
    File.mkdir_p!(context.cache)
    File.mkdir_p!(outside)
    File.ln_s!(outside, objects)
    artifact = write_artifact(context, @identity, "artifact.tar")

    assert {:error, errors} = adopt(context, artifact, @identity)
    assert Enum.any?(errors, &String.contains?(&1, "cache objects is symlink"))

    assert {:error, message} = Cache.garbage_collect(context.cache)
    assert message =~ "cache objects is symlink"
  end

  defp adopt(context, artifact, identity) do
    Cache.adopt(
      artifact,
      context.descriptor,
      "linux-x86-64",
      identity,
      context.cache
    )
  end

  defp inspect_cache(context, identity) do
    Cache.inspect(context.cache, identity, context.descriptor, "linux-x86-64")
  end

  defp write_artifact(context, identity, name, opts \\ []) do
    assert {:ok, manifest} =
             PayloadManifest.build(
               context.descriptor,
               "linux-x86-64",
               identity,
               context.payload
             )

    assert {:ok, manifest_bytes} = PayloadManifest.encode(manifest)
    content = File.read!(Path.join([context.payload, "bin", "tool"]))

    Tar.write!(
      Path.join(context.root, name),
      [
        %{
          path: Archive.manifest_path(),
          kind: :file,
          content: manifest_bytes,
          mode: 0o644
        },
        %{path: "bin/tool", kind: :file, content: content, mode: 0o755}
      ],
      opts
    )
  end

  defp stage_names(cache) do
    objects = Path.join(cache, "objects")

    if File.dir?(objects) do
      objects
      |> File.ls!()
      |> Enum.filter(&String.contains?(&1, ".stage-"))
    else
      []
    end
  end

  defp entry_path(cache, identity), do: Path.join([cache, "objects", identity])

  defp descriptor do
    %Descriptor{
      package: "native",
      profile: "production",
      kind: "executable",
      targets: [%{name: "linux-x86-64", status: :supported, reason: nil}],
      raw: %{
        "outputs" => [
          %{
            "path" => "bin/tool",
            "kind" => "file",
            "mode" => 0o755,
            "required" => true
          }
        ]
      }
    }
  end
end
