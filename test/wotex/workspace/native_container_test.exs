defmodule Wotex.Workspace.NativeContainerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace
  alias Wotex.Workspace.NativeCache
  alias Wotex.Workspace.NativeContainer
  alias WotexWorkspace.Fixtures

  test "gives the Linux container a tun device only when a requirement asks for one" do
    assert NativeContainer.run_options(["linux"]) == []
    assert NativeContainer.run_options([]) == []

    assert NativeContainer.run_options(["linux", "tun"]) ==
             ["--cap-add", "NET_ADMIN", "--device", "/dev/net/tun"]
  end

  test "tags an image by its Dockerfile and platform", context do
    root = Fixtures.tmp_dir(context)
    Fixtures.write!(root, "tooling/native/docker/sdk.Dockerfile", "FROM scratch\n")
    dockerfile = "tooling/native/docker/sdk.Dockerfile"

    tag = NativeContainer.tag(root, dockerfile, nil)
    assert tag =~ ~r/^wotex-native-sdk:[0-9a-f]{16}$/
    assert NativeContainer.tag(root, dockerfile, nil) == tag
    refute NativeContainer.tag(root, dockerfile, "linux/amd64") == tag

    File.write!(Path.join(root, dockerfile), "FROM scratch\nRUN true\n")
    refute NativeContainer.tag(root, dockerfile, nil) == tag
  end

  test "builds images only from tooling/native/docker", context do
    root = Fixtures.tmp_dir(context)

    assert {:error, message} = NativeContainer.image(root, "docker/sdk.Dockerfile", nil)
    assert message =~ "tooling/native/docker/<name>.Dockerfile"

    assert {:error, message} =
             NativeContainer.image(root, "tooling/native/docker/absent.Dockerfile", nil)

    assert message =~ "not found"
    assert NativeContainer.linux_dockerfile() == "tooling/native/docker/linux.Dockerfile"
  end

  test "maps container paths to host paths through the longest volume" do
    volumes = [
      {"/c/ws", "/work"},
      {"/r/packages/p", "/src"},
      {"/r/packages/p/native/src", "/work/sdk/host/src"}
    ]

    assert NativeContainer.to_host(volumes, "/work/sdk/host/src/a.cpp") ==
             "/r/packages/p/native/src/a.cpp"

    assert NativeContainer.to_host(volumes, "/work/build/gen/x.h") == "/c/ws/build/gen/x.h"
    assert NativeContainer.to_host(volumes, "/src") == "/r/packages/p"
    assert NativeContainer.to_host(volumes, "/srcx/a.cpp") == nil
    assert NativeContainer.to_host(volumes, "/usr/include/stdio.h") == nil
  end

  test "filters headers to volumes of package directories and rewrites reported paths",
       context do
    root = NativeCache.real_path(Fixtures.tmp_dir(context))
    package = Path.join(root, "packages/p")

    volumes = [
      {"/c/ws", "/work"},
      {package, "/src"},
      {Path.join(package, "native/src"), "/work/sdk/host/src"}
    ]

    assert NativeContainer.header_filter(volumes, root) == "^(/src/|/work/sdk/host/src/)"

    output = """
    ../sdk/host/src/a.cpp:3:1: error: finding [check]
    /src/include/p.hpp:9:2: note: here
    In file included from /work/sdk/src/lib.h:1:
    """

    assert NativeContainer.to_repository(output, volumes, root: root, directory: "/work/build") ==
             """
             packages/p/native/src/a.cpp:3:1: error: finding [check]
             packages/p/include/p.hpp:9:2: note: here
             In file included from /c/ws/sdk/src/lib.h:1:
             """
  end

  test "expands volume placeholders and wraps commands in docker exec", context do
    root = Fixtures.tmp_dir(context)
    File.mkdir_p!(Path.join(root, "ws"))
    container = %{dockerfile: "d", platform: nil, volumes: [{"{workspace}", "/work"}]}

    assert NativeContainer.volumes(container, %{"workspace" => Path.join(root, "ws")}) ==
             [{NativeCache.real_path(Path.join(root, "ws")), "/work"}]

    session = %{name: "c1", image: "i", volumes: []}

    assert NativeContainer.exec_argv(session, ["ninja", "-t", "compdb"]) ==
             ~w(docker exec c1 ninja -t compdb)

    assert NativeContainer.exec_argv(session, ["x"], env: [{"A", "1"}], cd: "/work") ==
             ~w(docker exec --env A=1 --workdir /work c1 x)
  end

  test "the Linux container finds the Mix wrapper first and trusts the mounted repository" do
    env = Map.new(NativeContainer.linux_env("/r", "/c"))
    assert env["WOTEX_ROOT"] == "/r"
    assert env["WOTEX_NATIVE_CACHE"] == "/c"
    assert env["WOTEX_MIX_STATE"] == "/c/linux-container/mix"
    assert env["HEX_HOME"] == "/c/linux-container/hex"
    assert String.starts_with?(env["PATH"], "/r/tooling/native/docker/bin:")
    assert {env["GIT_CONFIG_KEY_0"], env["GIT_CONFIG_VALUE_0"]} == {"safe.directory", "*"}

    # The entry point runs the root task it is given for the package.
    entry = File.read!(Path.join(Workspace.root(), "tooling/native/docker/suite.sh"))
    assert entry =~ ~s(exec mix "$task" --package "$package" "$@")

    # The wrapper and the entry point run from the read-only mount.
    for script <- ~w(tooling/native/docker/bin/mix tooling/native/docker/suite.sh) do
      %File.Stat{mode: mode} = File.stat!(Path.join(Workspace.root(), script))
      assert Bitwise.band(mode, 0o111) != 0, "#{script} is not executable"
    end
  end
end
