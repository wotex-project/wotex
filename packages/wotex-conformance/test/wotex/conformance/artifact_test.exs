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
    assert {:error, %{code: :invalid_artifact_type}} = Artifact.digest_file(link)
    assert {:error, %{code: :invalid_artifact_type}} = Artifact.digest_file(root)
  end

  test "counts empty, exact-budget, and multi-chunk artifacts from the bytes hashed", %{
    root: root
  } do
    path = Path.join(root, "bounded.bin")

    for size <- [0, 1, 65_535, 65_536, 65_537, 131_072] do
      contents = :binary.copy(<<17>>, size)
      expected = digest(contents)
      File.write!(path, contents)

      assert {:ok, %{digest: ^expected, size_bytes: ^size}} =
               Artifact.verify(path, expected, max_bytes: max(size, 1))

      assert {:ok, ^expected} = Artifact.digest_file(path)
    end
  end

  test "streaming reads reject one byte beyond budgets on either side of chunk boundaries", %{
    root: root
  } do
    path = Path.join(root, "over-budget.bin")

    for budget <- [1, 65_535, 65_536, 65_537, 131_072] do
      contents = :binary.copy(<<23>>, budget + 1)
      File.write!(path, contents)

      assert {:error, error} = Artifact.verify(path, digest(contents), max_bytes: budget)
      assert error.code == :limit_exceeded
      assert error.details == %{"max_bytes" => budget}
    end
  end

  test "changed contents fail the original digest and report their current verified size", %{
    root: root
  } do
    path = Path.join(root, "changed.bin")
    original = :binary.copy(<<31>>, 131_072)
    File.write!(path, original)
    original_digest = digest(original)

    for changed <- [binary_part(original, 0, 65_537), original <> <<1>>] do
      File.write!(path, changed)

      assert {:error, %{code: :artifact_digest_mismatch}} = Artifact.verify(path, original_digest)

      assert {:ok, verification} = Artifact.verify(path, digest(changed))
      assert verification.size_bytes == byte_size(changed)
      assert verification.digest == digest(changed)
    end
  end

  defp digest(contents),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, contents), case: :lower)
end
