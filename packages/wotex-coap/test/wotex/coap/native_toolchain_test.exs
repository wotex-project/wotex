defmodule Wotex.CoAP.Native.ToolchainTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP.Native.Toolchain

  @keys [:cc, :cmake, :curl, :openssl, :patch, :pkg_config, :system]

  test "WCO-N01 explicit tool identities bind absolute executable bytes" do
    executable = System.find_executable("true")
    paths = Map.new(@keys, &{&1, executable})
    root = System.tmp_dir!()
    assert {:ok, tools} = Toolchain.identify(paths, root, {:linux, :x86_64})
    assert map_size(tools.hashes) == length(@keys)
    assert tools.openssl_root == root
    assert Enum.all?(tools.hashes, fn {_, value} -> value =~ ~r/\A[0-9a-f]{64}\z/ end)
    assert Enum.all?(tools.paths, fn {_, value} -> Path.type(value) == :absolute end)

    commands = Toolchain.version_commands(tools)
    assert length(commands) == 7
    assert {:system, ^executable, ["--version"]} = List.last(commands)

    assert {:ok, darwin} = Toolchain.identify(paths, root, {:darwin, :aarch64})
    assert {:system, ^executable, []} = List.last(Toolchain.version_commands(darwin))
  end

  test "WCO-N01 real selected host resolves a supported complete toolchain" do
    assert {:ok, toolchain} = Toolchain.resolve()
    assert toolchain.target in [{:linux, :x86_64}, {:linux, :aarch64}, {:darwin, :aarch64}]
    assert Map.keys(toolchain.paths) |> Enum.sort() == Enum.sort(@keys)
    assert Enum.all?(toolchain.paths, fn {_, path} -> File.regular?(path) end)
    assert File.dir?(toolchain.openssl_root)
  end

  test "WCO-N01 missing tools, unsupported targets and extra keys fail explicitly" do
    executable = System.find_executable("true")
    paths = Map.new(@keys, &{&1, executable})
    root = System.tmp_dir!()
    assert {:error, :invalid_native_toolchain} = Toolchain.identify(nil, nil, nil)

    assert {:error, :unsupported_native_target} =
             Toolchain.identify(paths, root, {:linux, :unknown})

    assert {:error, :invalid_native_toolchain} =
             Toolchain.identify(Map.delete(paths, :cc), root, {:linux, :x86_64})

    assert {:error, :invalid_native_toolchain} =
             Toolchain.identify(paths, "relative", {:linux, :x86_64})

    for path <- [nil, "relative", "/no-such-wotex-compiler", root] do
      assert {:error, {:missing_native_tool, :cc}} =
               Toolchain.identify(Map.put(paths, :cc, path), root, {:linux, :x86_64})
    end

    assert Toolchain.target({:unix, :darwin}, ~c"arm64-apple-darwin") == {:darwin, :aarch64}
    assert Toolchain.target({:unix, :linux}, ~c"aarch64-linux-gnu") == {:linux, :aarch64}
    assert Toolchain.target({:unix, :linux}, ~c"x86_64-linux-gnu") == {:linux, :x86_64}
    assert Toolchain.target({:unix, :linux}, ~c"riscv64-linux-gnu") == {:linux, :unsupported}
    assert Toolchain.target({:win32, :nt}, ~c"x86_64") == {:unsupported, :unsupported}
  end

  test "WCO-N01 linked tools resolve while loops and nonexecutables fail", context do
    root = temporary(context)
    tool = Path.join(root, "tool")
    File.write!(tool, "not-executable")
    link = Path.join(root, "link")
    File.ln_s!("tool", link)
    executable = System.find_executable("true")
    paths = Map.new(@keys, &{&1, executable})

    assert {:error, {:missing_native_tool, :cc}} =
             Toolchain.identify(Map.put(paths, :cc, link), root, {:linux, :x86_64})

    File.chmod!(tool, 0o700)
    assert {:ok, selected} = Toolchain.identify(Map.put(paths, :cc, link), root, {:linux, :x86_64})
    assert selected.paths.cc == tool
    File.rm!(link)
    File.ln_s!("link", link)

    assert {:error, {:missing_native_tool, :cc}} =
             Toolchain.identify(Map.put(paths, :cc, link), root, {:linux, :x86_64})
  end

  test "WCO-N01 CC, CMAKE and OPENSSL_ROOT_DIR select the caller toolchain", context do
    root = temporary(context)
    bin = Path.join(root, "bin")
    File.mkdir!(bin)
    executable = System.find_executable("true")

    for name <- ["cc", "cmake", "openssl"] do
      File.ln_s!(executable, Path.join(bin, name))
    end

    variables = ["CC", "CMAKE", "OPENSSL_ROOT_DIR", "PATH"]
    original = Map.take(System.get_env(), variables)

    try do
      System.put_env("CC", Path.join(bin, "cc"))
      System.put_env("CMAKE", Path.join(bin, "cmake"))
      System.put_env("OPENSSL_ROOT_DIR", root)
      assert {:ok, tools} = Toolchain.resolve()
      assert tools.paths.cc == executable
      assert tools.paths.cmake == executable
      assert tools.paths.openssl == executable
      assert tools.openssl_root == root

      System.put_env("CC", "")
      assert {:error, {:invalid_native_tool, "CC"}} = Toolchain.resolve()
      System.put_env("CC", Path.join(bin, "cc"))
      System.put_env("OPENSSL_ROOT_DIR", "relative")
      assert {:error, :invalid_openssl_root} = Toolchain.resolve()
      System.put_env("OPENSSL_ROOT_DIR", root)
      System.put_env("PATH", root)
      assert {:error, {:missing_native_tool, missing}} = Toolchain.resolve()
      assert missing in [:curl, :patch, :pkg_config, :system]
    after
      Enum.each(variables, &System.delete_env/1)
      Enum.each(original, fn {key, value} -> System.put_env(key, value) end)
    end
  end

  defp temporary(context) do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-toolchain-#{context.test}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
