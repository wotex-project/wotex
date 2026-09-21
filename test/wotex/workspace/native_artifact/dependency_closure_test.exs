defmodule Wotex.Workspace.NativeArtifact.DependencyClosureTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Manifest.NativeArtifactInput
  alias Wotex.Workspace.Manifest.NativeArtifactTarget
  alias Wotex.Workspace.NativeArtifact.DependencyClosure
  alias Wotex.Workspace.NativeArtifact.DependencyClosure.Artifact
  alias Wotex.Workspace.NativeArtifact.DependencyClosure.Limits
  alias WotexWorkspace.Fixtures
  alias WotexWorkspace.NativeArtifactELFFixture, as: ELF

  @build String.duplicate("a", 64)
  @payload String.duplicate("b", 64)

  setup context do
    root = Fixtures.tmp_dir(context)
    rootfs = Path.join(root, "rootfs")
    application = Path.join(root, "application")
    File.mkdir_p!(rootfs)
    File.mkdir_p!(application)
    %{root: root, rootfs: rootfs, application: application}
  end

  test "closes dependencies through the exact rootfs and retains system identity", context do
    rootfs_provider(context, "usr/lib/libc.so.6", soname: "libc.so.6")

    rootfs_provider(context, "usr/lib64/ld-linux-x86-64.so.2",
      soname: "ld-linux-x86-64.so.2",
      needed: ["libc.so.6"]
    )

    File.ln_s!("usr/lib", Path.join(context.rootfs, "lib"))
    File.ln_s!("usr/lib64", Path.join(context.rootfs, "lib64"))

    artifact_provider(context.application, "bin/tool",
      interpreter: "/lib64/ld-linux-x86-64.so.2",
      needed: ["libc.so.6"]
    )

    assert {:ok, result} =
             check([artifact("application", context.application)], context.rootfs)

    assert result.target == "linux-x86-64"
    assert result.system == "fixture-system"
    assert result.system_identity == "fixture-system-v1"

    assert Enum.map(result.files, & &1["id"]) == [
             "application:bin/tool",
             "rootfs:usr/lib/libc.so.6",
             "rootfs:usr/lib64/ld-linux-x86-64.so.2"
           ]

    assert Enum.any?(result.edges, fn edge ->
             edge["kind"] == "interpreter" and
               edge["provider"] == "rootfs:usr/lib64/ld-linux-x86-64.so.2"
           end)

    assert Enum.count(result.edges, &(&1["name"] == "libc.so.6")) == 2
  end

  test "resolves a dependency from an admitted sibling artifact", context do
    library = Path.join(context.root, "library")
    File.mkdir_p!(library)
    artifact_provider(context.application, "bin/tool", needed: ["libshared.so.1"])

    artifact_provider(library, "lib/libshared.so.1.2",
      soname: "libshared.so.1",
      type: "shared"
    )

    assert {:ok, result} =
             check(
               [artifact("application", context.application), artifact("library", library)],
               context.rootfs
             )

    assert [edge] = result.edges
    assert edge["provider"] == "library:lib/libshared.so.1.2"
    assert edge["provider_digest"] =~ ~r/^[0-9a-f]{64}$/
  end

  test "aggregates missing interpreter, unresolved libraries and wrong architecture", context do
    artifact_provider(context.application, "bin/tool",
      interpreter: "/lib64/missing-loader.so",
      needed: ["libwrong.so", "libmissing.so"]
    )

    rootfs_provider(context, "lib/libwrong.so",
      architecture: "aarch64",
      soname: "libwrong.so"
    )

    assert {:error, errors} =
             check([artifact("application", context.application)], context.rootfs)

    assert Enum.any?(errors, &String.contains?(&1, "unresolved interpreter"))
    assert Enum.any?(errors, &String.contains?(&1, "unresolved DT_NEEDED libmissing.so"))
    assert Enum.any?(errors, &String.contains?(&1, "incompatible ELF architecture"))
  end

  test "reports every architecture, class and endianness mismatch", context do
    artifact_provider(context.application, "bin/tool",
      needed: ["libarch.so", "libclass.so", "libendian.so"]
    )

    rootfs_provider(context, "lib/libarch.so",
      architecture: "aarch64",
      soname: "libarch.so"
    )

    rootfs_provider(context, "lib/libclass.so",
      architecture: "x86",
      class: "elf32",
      soname: "libclass.so"
    )

    rootfs_provider(context, "lib/libendian.so",
      endianness: "big",
      soname: "libendian.so"
    )

    assert {:error, errors} =
             check([artifact("application", context.application)], context.rootfs)

    assert Enum.any?(errors, &String.contains?(&1, "lib/libarch.so: incompatible ELF architecture"))
    assert Enum.any?(errors, &String.contains?(&1, "lib/libclass.so: incompatible ELF class"))
    assert Enum.any?(errors, &String.contains?(&1, "lib/libendian.so: incompatible ELF endianness"))
  end

  test "walks sibling dependencies transitively and reports their unresolved libraries", context do
    library = Path.join(context.root, "library")
    File.mkdir_p!(library)
    artifact_provider(context.application, "bin/tool", needed: ["libshared.so.1"])

    artifact_provider(library, "lib/libshared.so.1",
      soname: "libshared.so.1",
      type: "shared",
      needed: ["libtransitive-one.so", "libtransitive-two.so"]
    )

    assert {:error, errors} =
             check(
               [artifact("application", context.application), artifact("library", library)],
               context.rootfs
             )

    assert Enum.any?(errors, &String.contains?(&1, "unresolved DT_NEEDED libtransitive-one.so"))
    assert Enum.any?(errors, &String.contains?(&1, "unresolved DT_NEEDED libtransitive-two.so"))
  end

  test "does not satisfy dependencies from the host and rejects non-ELF matches", context do
    artifact_provider(context.application, "bin/tool", needed: ["libc.so.6"])
    Fixtures.write!(context.rootfs, "lib/libc.so.6", "host-looking filename")

    assert {:error, errors} =
             check([artifact("application", context.application)], context.rootfs)

    assert errors == ["application:bin/tool: unresolved DT_NEEDED libc.so.6"]
  end

  test "reports conflicting providers without order-dependent selection", context do
    first = Path.join(context.root, "first")
    second = Path.join(context.root, "second")
    File.mkdir_p!(first)
    File.mkdir_p!(second)
    artifact_provider(context.application, "bin/tool", needed: ["libshared.so.1"])
    artifact_provider(first, "lib/a.so", soname: "libshared.so.1", type: "shared")

    artifact_provider(second, "lib/b.so",
      soname: "libshared.so.1",
      type: "shared",
      needed: ["libextra.so"]
    )

    assert {:error, errors} =
             check(
               [
                 artifact("application", context.application),
                 artifact("first", first),
                 artifact("second", second)
               ],
               context.rootfs
             )

    assert Enum.any?(errors, fn error ->
             error =~ "conflicting providers for DT_NEEDED libshared.so.1" and
               error =~ "first:lib/a.so" and error =~ "second:lib/b.so"
           end)
  end

  test "treats byte-identical providers as equivalent", context do
    first = Path.join(context.root, "first")
    second = Path.join(context.root, "second")
    File.mkdir_p!(first)
    File.mkdir_p!(second)
    artifact_provider(context.application, "bin/tool", needed: ["libshared.so.1"])
    artifact_provider(first, "lib/a.so", soname: "libshared.so.1", type: "shared")
    artifact_provider(second, "lib/b.so", soname: "libshared.so.1", type: "shared")

    assert {:ok, result} =
             check(
               [
                 artifact("application", context.application),
                 artifact("first", first),
                 artifact("second", second)
               ],
               context.rootfs
             )

    edge = Enum.find(result.edges, &(&1["name"] == "libshared.so.1"))
    assert edge["equivalent_providers"] == ["first:lib/a.so", "second:lib/b.so"]
  end

  test "rejects escaping and cyclic rootfs links", context do
    File.mkdir_p!(Path.join(context.rootfs, "lib"))
    File.ln_s!("../../../outside", Path.join(context.rootfs, "lib/escape"))
    artifact_provider(context.application, "bin/tool")

    assert {:error, errors} =
             check([artifact("application", context.application)], context.rootfs)

    assert Enum.any?(errors, &String.contains?(&1, "escapes the source root"))

    File.rm!(Path.join(context.rootfs, "lib/escape"))
    File.ln_s!("two", Path.join(context.rootfs, "one"))
    File.ln_s!("one", Path.join(context.rootfs, "two"))

    assert {:error, errors} =
             check([artifact("application", context.application)], context.rootfs)

    assert Enum.any?(errors, &String.contains?(&1, "symlink cycle"))
  end

  test "enforces assembly bounds and refuses a non-ELF fallback", context do
    Fixtures.write!(context.application, "bin/tool", "not elf")

    assert {:error, errors} =
             check([artifact("application", context.application)], context.rootfs)

    assert errors == ["assembly artifacts contain no ELF files; no format fallback is permitted"]

    Fixtures.write!(context.rootfs, "one", "1")
    Fixtures.write!(context.rootfs, "two", "2")

    assert {:error, errors} =
             DependencyClosure.check(
               [artifact("application", context.application)],
               context.rootfs,
               target(),
               system(),
               %Limits{entries: 1}
             )

    assert Enum.any?(errors, &String.contains?(&1, "tree exceeds 1 entries"))
  end

  test "validates artifact target, identities and root ownership", context do
    linked = Path.join(context.root, "linked-rootfs")
    File.ln_s!(context.rootfs, linked)

    invalid = %Artifact{
      name: "application",
      path: context.application,
      target: "linux-aarch64",
      build_identity: "short",
      payload_identity: @payload
    }

    assert {:error, errors} =
             DependencyClosure.check([invalid], linked, target(), system())

    assert Enum.any?(errors, &String.contains?(&1, "root filesystem is symlink"))
    assert Enum.any?(errors, &String.contains?(&1, "targets linux-aarch64"))
    assert Enum.any?(errors, &String.contains?(&1, "invalid build identity"))
  end

  defp check(artifacts, rootfs) do
    DependencyClosure.check(artifacts, rootfs, target(), system())
  end

  defp artifact(name, path) do
    %Artifact{
      name: name,
      path: path,
      target: "linux-x86-64",
      build_identity: @build,
      payload_identity: @payload
    }
  end

  defp artifact_provider(root, relative, opts \\ []) do
    ELF.write!(Path.join(root, relative), opts)
  end

  defp rootfs_provider(context, relative, opts) do
    ELF.write!(Path.join(context.rootfs, relative), opts)
  end

  defp target do
    %NativeArtifactTarget{
      name: "linux-x86-64",
      operating_system: "linux",
      architecture: "x86_64",
      endianness: "little",
      libc: "glibc",
      abi: "gnu",
      toolchain: "fixture-toolchain",
      system: "fixture-system"
    }
  end

  defp system do
    %NativeArtifactInput{
      name: "fixture-system",
      identity: "fixture-system-v1",
      inputs: []
    }
  end
end
