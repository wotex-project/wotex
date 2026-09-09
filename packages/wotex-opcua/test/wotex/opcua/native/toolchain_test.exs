defmodule Wotex.OPCUA.Native.ToolchainTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Native.Toolchain

  @keys [:cc, :cmake, :ctest, :make, :perl, :python, :ar, :ranlib, :curl, :linker, :system]

  test "WOP-X02 explicit tool identities bind absolute executable bytes" do
    paths = Map.new(@keys, &{&1, System.find_executable("true")})
    assert {:ok, tools} = Toolchain.identify(paths, {:linux, :x86_64})
    assert map_size(tools.hashes) == 11
    assert map_size(tools.recipe) == 8
    assert Enum.all?(tools.hashes, fn {_, value} -> value =~ ~r/\A[0-9a-f]{64}\z/ end)
    assert Enum.all?(tools.paths, fn {_, value} -> Path.type(value) == :absolute end)
    steps = Toolchain.version_steps(tools, "/tmp")
    assert length(steps) == 9
    assert Enum.find(steps, &(&1.id == :linker)).args == ["--version"]
    assert Enum.all?(steps, &(&1.timeout_ms == 5000 and &1.output_bytes == 65_536))
    assert {:ok, darwin} = Toolchain.identify(paths, {:darwin, :aarch64})
    assert Enum.find(Toolchain.version_steps(darwin, "/tmp"), &(&1.id == :linker)).args == ["-v"]
    assert Enum.find(Toolchain.version_steps(darwin, "/tmp"), &(&1.id == :system)).args == []
  end

  test "WOP-X02 real selected host has a supported, complete identified toolchain" do
    assert {:ok, toolchain} = Toolchain.resolve()
    assert toolchain.target in [{:linux, :x86_64}, {:linux, :aarch64}, {:darwin, :aarch64}]
    assert Enum.all?(toolchain.paths, fn {_, path} -> File.regular?(path) end)
  end

  test "WOP-X02 missing tools, unsupported targets and extra keys fail explicitly" do
    paths = Map.new(@keys, &{&1, System.find_executable("true")})
    assert {:error, :invalid_native_toolchain} = Toolchain.identify(nil, nil)
    assert {:error, :unsupported_native_target} = Toolchain.identify(paths, {:linux, :unknown})

    assert {:error, :invalid_native_toolchain} =
             Toolchain.identify(Map.delete(paths, :cc), {:linux, :x86_64})

    for path <- [nil, "relative", "/no-such-wotex-compiler", "/tmp"] do
      assert {:error, {:missing_native_tool, :cc}} =
               Toolchain.identify(Map.put(paths, :cc, path), {:linux, :x86_64})
    end
  end

  test "WOP-X02 linked tools resolve to their bytes while link loops and nonexecutables fail" do
    dir =
      Path.join(System.tmp_dir!(), "wotex-opcua-toolchain-#{System.unique_integer([:positive])}")

    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    tool = Path.join(dir, "tool")
    File.write!(tool, "not-executable")
    link = Path.join(dir, "link")
    File.ln_s!("tool", link)
    paths = Map.new(@keys, &{&1, System.find_executable("true")})

    assert {:error, {:missing_native_tool, :cc}} =
             Toolchain.identify(Map.put(paths, :cc, link), {:linux, :x86_64})

    File.chmod!(tool, 0o700)
    assert {:ok, selected} = Toolchain.identify(Map.put(paths, :cc, link), {:linux, :x86_64})
    assert selected.paths.cc == tool
    File.rm!(link)
    File.ln_s!("link", link)

    assert {:error, {:missing_native_tool, :cc}} =
             Toolchain.identify(Map.put(paths, :cc, link), {:linux, :x86_64})
  end
end
