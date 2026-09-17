defmodule Wotex.Thread.NativeBuildTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.BuildFixture
  alias Wotex.Thread.Native.Build

  @moduletag requirements: ["WTH-B01", "WTH-B04"]

  setup do
    root = Path.join(File.cwd!(), ".wotex-thread-build-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, workspace: Path.join(root, "workspace")}
  end

  test "WTH-B01 the production environment reads pinned sources without touching them" do
    environment = Build.environment()
    assert environment.platform == :os.type()
    assert environment.search_path == nil
    assert File.regular?(Path.join(environment.native, "dependencies.json"))
    assert is_function(environment.fetch, 3)
  end

  test "WTH-B01 arguments, platform and tools are checked before workspace mutation", context do
    environment = BuildFixture.environment(context.root)

    assert {:error, :invalid_build_workspace} = Build.run(:workspace, false, environment)
    assert {:error, :invalid_build_workspace} = Build.run("relative", false, environment)

    assert {:error, :linux_required} =
             Build.run(context.workspace, false, %{environment | platform: {:unix, :darwin}})

    missing = BuildFixture.environment(Path.join(context.root, "missing"), missing_tools: ["ninja"])
    assert {:error, {:missing_native_tool, "ninja"}} = Build.run(context.workspace, false, missing)

    invalid = Path.join(context.root, "invalid")
    File.mkdir_p!(invalid)
    File.write!(Path.join(invalid, "dependencies.json"), "{}")

    assert {:error, :invalid_native_pins} =
             Build.run(context.workspace, false, %{environment | native: invalid})

    refute File.exists?(context.workspace)
  end

  test "WTH-B04 a pinned build records its sources, fixes, tools and artifacts", context do
    environment = BuildFixture.environment(context.root)
    workspace = context.workspace

    assert {:ok, %{reused: false, manifest: manifest}} = Build.run(workspace, false, environment)
    assert manifest["schema"] == "wotex.native-build" and manifest["package"] == "wotex_thread"
    assert manifest["build_features"] == %{"sanitizers" => false}
    assert manifest["environment_allowlist"] == ~w(HOME LC_ALL PATH TMPDIR)

    pins = BuildFixture.pins(environment.native)

    sdk =
      Path.join([
        workspace,
        "sources/openthread",
        "openthread-#{pins["sources"]["openthread"]["commit"]}"
      ])

    # The reviewed SDK fixes were applied to the extracted sources, not to the archive.
    spinel = File.read!(Path.join(sdk, "src/lib/spinel/spinel.c"))
    assert spinel =~ "(uint32_t)data_in[3]" and spinel =~ "(uint32_t)data_in[7]"
    assert File.read!(Path.join(sdk, "src/core/meshcop/meshcop.hpp")) =~ "mLength == 64"
    assert File.regular?(Path.join(sdk, "third_party/mbedtls/repo/include/mbedtls.h"))

    assert File.regular?(
             Path.join(sdk, "third_party/mbedtls/repo/framework/include/mbedtls-framework.h")
           )

    audit = manifest["audit"]
    assert audit["binary"]["path"] == "build/wotex-thread-host"
    assert audit["binary"]["elf_machine"] == "AArch64"
    assert audit["binary"]["needed_libraries"] == ["libc.so.6"]
    assert audit["json_header_sha256"] == pins["json"]["sha256"]
    assert audit["native_runtime_started"] == false
    assert audit["target_triple"] == "aarch64-unknown-linux-gnu"
    assert manifest["toolchain"]["versions"]["version_cmake"] == "cmake version 3.25.1"
    assert manifest["binaries"] == [audit["binary"]]

    for name <- ~w(bootstrap version_cmake version_ninja version_cc version_cxx version_readelf
                   target configure compile elf needed) do
      assert File.regular?(Path.join(workspace, "logs/#{name}.log")), name
    end

    assert File.regular?(Path.join(workspace, "bin/build-command"))
    refute File.exists?(Path.join(workspace, ".wotex-thread-build.lock"))

    # A completed workspace verifies without rebuilding; every build log is exclusive.
    assert {:ok, %{reused: true, manifest: ^manifest}} = Build.run(workspace, false, environment)

    File.write!(Path.join(workspace, "build/wotex-thread-host"), "changed")
    assert {:error, :build_manifest_mismatch} = Build.run(workspace, false, environment)
  end

  test "WTH-B01 a sanitizer build is a separate identity in its own workspace", context do
    environment = BuildFixture.environment(context.root)

    assert {:ok, %{reused: false, manifest: normal}} =
             Build.run(context.workspace, false, environment)

    sanitized = Path.join(context.root, "sanitized")
    assert {:ok, %{reused: false, manifest: instrumented}} = Build.run(sanitized, true, environment)
    assert instrumented["build_features"] == %{"sanitizers" => true}
    assert normal["identity"] != instrumented["identity"]

    assert Enum.any?(
             instrumented["arguments"]["configure"],
             &(&1 == "-DWOTEX_NATIVE_SANITIZERS=ON")
           )

    assert {:error, :build_manifest_mismatch} = Build.run(sanitized, false, environment)
  end

  test "WTH-B01 a refused build command leaves an unusable workspace", context do
    environment = BuildFixture.environment(context.root, failing_tool: :cmake)

    assert {:error, {:command_failed, :version_cmake, 3}} =
             Build.run(context.workspace, false, environment)

    assert File.read!(Path.join(context.workspace, "logs/version_cmake.log")) =~ "refused"
    refute File.exists?(Path.join(context.workspace, "native-manifest.json"))

    working = BuildFixture.environment(context.root)
    assert {:error, :build_workspace_locked} = Build.run(context.workspace, false, working)
    assert File.regular?(Path.join(context.workspace, ".wotex-thread-build.lock"))
  end

  test "WTH-B01 an unavailable pinned transfer fails the build", context do
    environment = BuildFixture.environment(context.root)
    offline = %{environment | fetch: fn _, _, _ -> {:error, :invalid_source_download} end}
    assert {:error, :invalid_source_download} = Build.run(context.workspace, false, offline)
    refute File.exists?(Path.join(context.workspace, "native-manifest.json"))
  end
end
