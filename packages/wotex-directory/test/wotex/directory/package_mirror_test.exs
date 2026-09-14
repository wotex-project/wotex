Code.require_file("bin/evidence.exs")

defmodule Wotex.Directory.PackageMirrorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  setup do
    {output, 0} =
      System.cmd("mktemp", ["-d", Path.join(System.tmp_dir!(), "directory-package-test.XXXXXX")],
        env: [{"ERL_FLAGS", nil}, {"ELIXIR_ERL_OPTIONS", nil}]
      )

    root = String.trim(output)
    on_exit(fn -> File.rm_rf!(root) end)

    mirror =
      DirectoryPackageMirror.prepare!(File.cwd!(), root, Mix.Project.config()[:package][:files])

    archive = Path.join(root, "unpacked")

    for path <- Map.keys(mirror.inputs) do
      target = Path.join(archive, path)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(Path.join(mirror.directory, path), target)
    end

    %{root: root, mirror: mirror, archive: archive}
  end

  test "the external mirror retains exact public bytes and deliberately excluded state",
       context do
    %{mirror: mirror, archive: archive} = context
    assert map_size(mirror.sentinels) >= 20
    assert Map.has_key?(mirror.sentinels, "docs/tasks/local/exclusion-sentinel.json")

    for {path, expected} <- mirror.inputs do
      assert DirectoryEvidence.digest(path) == expected
      assert DirectoryEvidence.digest(Path.join(mirror.directory, path)) == expected
    end

    proof = DirectoryPackageMirror.verify!(mirror, archive, "synthetic metadata")
    assert proof["member_sha256"] == mirror.inputs
    assert proof["sentinels_present_before_and_after_build"]
    assert proof["sentinel_paths_absent"]
    assert proof["sentinel_bytes_absent"]

    assert Map.keys(proof["excluded_sentinels"]) |> Enum.sort() ==
             Map.keys(mirror.sentinels) |> Enum.sort()
  end

  test "changed, missing and additional archive members fail byte correspondence", context do
    path = Path.join(context.archive, "README.md")
    original = File.read!(path)
    File.write!(path, original <> "changed")
    assert_mismatch(context)
    File.rm!(path)
    assert_mismatch(context)
    File.write!(path, original)
    File.write!(Path.join(context.archive, "unexpected.txt"), "extra")
    assert_mismatch(context)
  end

  test "full-gate evidence rejects replayed archives, incomplete sentinels and changed inputs",
       context do
    proof =
      context.mirror
      |> DirectoryPackageMirror.verify!(context.archive, "metadata")
      |> Map.merge(%{"sentinel_build" => true, "directory_build_count" => 1})

    allowlist = Mix.Project.config()[:package][:files]
    assert DirectoryPackageMirror.evidence!(proof, context.mirror.inputs, allowlist) == :ok

    for changed <- [
          nil,
          Map.put(proof, "sentinel_build", false),
          Map.put(proof, "directory_build_count", 2),
          Map.put(proof, "member_sha256", %{}),
          Map.put(proof, "excluded_sentinels", %{}),
          put_in(proof, ["excluded_sentinels", "AGENTS.md"], "not a digest"),
          Map.put(proof, "sentinel_paths_absent", false),
          Map.put(proof, "sentinel_bytes_absent", false)
        ] do
      assert_raise RuntimeError, ~r/fresh complete package-exclusion evidence/, fn ->
        DirectoryPackageMirror.evidence!(changed, context.mirror.inputs, allowlist)
      end
    end

    assert_raise RuntimeError, ~r/fresh complete package-exclusion evidence/, fn ->
      DirectoryPackageMirror.evidence!(
        proof,
        Map.put(context.mirror.inputs, "README.md", "changed"),
        allowlist
      )
    end
  end

  test "excluded paths and renamed sentinel bytes are independently rejected", context do
    {path, bytes} = Enum.at(context.mirror.sentinels, 0)
    target = Path.join(context.archive, path)
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, bytes)

    assert_raise RuntimeError, ~r/excluded sentinel path/, fn ->
      DirectoryPackageMirror.verify!(context.mirror, context.archive, "metadata")
    end

    File.rm!(target)
    File.write!(Path.join(context.archive, "README.md"), bytes)

    assert_raise RuntimeError, ~r/excluded sentinel bytes/, fn ->
      DirectoryPackageMirror.verify!(context.mirror, context.archive, "metadata")
    end
  end

  test "metadata cannot carry sentinel bytes and the build mirror must retain its sentinels",
       context do
    {path, bytes} = Enum.at(context.mirror.sentinels, 0)

    assert_raise RuntimeError, ~r/excluded sentinel bytes/, fn ->
      DirectoryPackageMirror.verify!(context.mirror, context.archive, bytes)
    end

    input = Path.join(context.mirror.directory, "README.md")
    original = File.read!(input)
    File.write!(input, original <> "changed")

    assert_raise RuntimeError, ~r/build mirror changed/, fn ->
      DirectoryPackageMirror.verify!(context.mirror, context.archive, "metadata")
    end

    File.write!(input, original)

    File.rm!(Path.join(context.mirror.directory, path))

    assert_raise RuntimeError, ~r/build mirror changed/, fn ->
      DirectoryPackageMirror.verify!(context.mirror, context.archive, "metadata")
    end
  end

  test "unsafe, recursive and non-regular source inputs are refused", context do
    source = Path.join(context.root, "source")
    File.mkdir_p!(Path.join(source, "lib"))
    File.mkdir_p!(Path.join(source, "docs"))
    File.write!(Path.join(source, "lib/unexpected.txt"), "not Elixir source")
    File.ln_s!(Path.join(context.archive, "README.md"), Path.join(source, "link"))

    for {input, message} <- [
          {"../README.md", ~r/unsafe package allowlist/},
          {"docs", ~r/non-regular package input/},
          {"link", ~r/non-regular package input/},
          {"lib", ~r/non-Elixir library input/}
        ] do
      destination = Path.join(context.root, "rejected-#{Path.basename(input)}")
      File.mkdir!(destination)

      assert_raise RuntimeError, message, fn ->
        DirectoryPackageMirror.prepare!(source, destination, [input])
      end
    end
  end

  test "even a temporary destination cannot be inside another repository", context do
    repository = Path.join(context.root, "repository")
    destination = Path.join(repository, "work")
    File.mkdir_p!(destination)
    File.mkdir!(Path.join(repository, ".git"))

    assert_raise RuntimeError, ~r/outside repositories/, fn ->
      DirectoryPackageMirror.prepare!(File.cwd!(), destination, ["README.md"])
    end

    refute File.exists?(Path.join(destination, "package-source"))
  end

  test "symlinks and source-tree destinations are not package mirror inputs", context do
    File.ln_s!(Path.join(context.archive, "README.md"), Path.join(context.archive, "link"))

    assert_raise RuntimeError, ~r/non-regular package input/, fn ->
      DirectoryPackageMirror.verify!(context.mirror, context.archive, "metadata")
    end

    assert_raise RuntimeError, ~r/system temporary directory/, fn ->
      DirectoryPackageMirror.prepare!(File.cwd!(), File.cwd!(), ["README.md"])
    end
  end

  defp assert_mismatch(context) do
    assert_raise RuntimeError, ~r/archive members differ from intended source bytes/, fn ->
      DirectoryPackageMirror.verify!(context.mirror, context.archive, "metadata")
    end
  end
end
