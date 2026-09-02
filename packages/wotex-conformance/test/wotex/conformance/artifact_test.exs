defmodule Wotex.Conformance.ArtifactTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.Artifact
  alias Wotex.Conformance.TestFixtures

  setup do
    {root, archive, digest} = TestFixtures.subject_archive!()
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, archive: archive, digest: digest}
  end

  test "verifies a regular archive by streaming digest", %{archive: archive, digest: digest} do
    assert {:ok, verification} = Artifact.verify(archive, digest)
    assert verification.digest == digest
    assert verification.size_bytes > 0
  end

  test "rejects a digest mismatch without returning archive bytes", %{archive: archive} do
    wrong = "sha256:" <> String.duplicate("0", 64)
    assert {:error, error} = Artifact.verify(archive, wrong)
    assert error.code == :artifact_digest_mismatch
    refute Map.has_key?(error.details, "bytes")
  end

  test "rejects symbolic links", %{root: root, archive: archive, digest: digest} do
    link = Path.join(root, "subject-link.tar.gz")
    File.ln_s!(archive, link)

    assert {:error, %{code: :invalid_artifact_type}} = Artifact.verify(link, digest)
  end
end
