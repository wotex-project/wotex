defmodule Wotex.Thread.SoftwareBuildTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.Software.Build

  @moduletag requirements: ["WTH-B01"]

  test "WTH-B01 software build accepts exactly one absolute workspace" do
    workspace = Path.join(System.tmp_dir!(), "wotex-thread-software-arguments")
    assert {:ok, ^workspace} = Build.arguments(["--workspace", workspace])

    for args <- [
          [],
          ["--workspace"],
          ["--workspace", "relative"],
          ["--workspace", "/"],
          ["--workspace", workspace, "--sanitizers"],
          ["--sanitizers", "--workspace", workspace],
          ["--workspace", workspace, "--workspace", workspace],
          ["--workspace", Path.join(workspace, "../escape")],
          [workspace]
        ] do
      assert {:error, :invalid_software_build_arguments} = Build.arguments(args)
    end

    assert {:error, :invalid_software_build_arguments} = Build.run(:workspace)
  end

  test "WTH-B01 fixture paths stay inside the selected workspace" do
    executables = Build.executables("/disposable/software")

    paths =
      Enum.flat_map(executables, fn
        {_, paths} when is_list(paths) -> paths
        {_, path} -> [path]
      end)

    assert length(executables.native_tests) == 6
    assert Enum.all?(paths, &String.starts_with?(&1, "/disposable/software/"))
    assert executables.rcp == "/disposable/software/fixtures/bin/ot-rcp"
  end

  if match?({:unix, :linux}, :os.type()) do
    test "WTH-B01 an unrelated Linux workspace is refused before building" do
      workspace =
        Path.join(System.tmp_dir!(), "wotex-thread-software-#{System.unique_integer([:positive])}")

      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "existing"), "keep")
      on_exit(fn -> File.rm_rf!(workspace) end)
      assert {:error, _} = Build.run(workspace)
      assert File.ls!(workspace) == ["existing"]
    end
  else
    test "WTH-B01 the software fixture build requires Linux before workspace mutation" do
      workspace =
        Path.join(System.tmp_dir!(), "wotex-thread-software-#{System.unique_integer([:positive])}")

      assert {:error, :linux_required} = Build.run(workspace)
      refute File.exists?(workspace)
    end
  end
end
