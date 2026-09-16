defmodule Wotex.OPCUA.Native.RecipeTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Native.Recipe

  @tools Map.new([:cc, :cmake, :ctest, :make, :perl, :python, :ar, :ranlib], &{&1, "/tools/#{&1}"})

  test "WOP-X02 recipe pins crypto/client flags and explicit host tools without executing them" do
    {:ok, steps} = Recipe.new("/isolated/workspace", "/package/native", @tools, {:linux, :x86_64})
    assert length(steps) == 11
    assert hd(steps).executable == "/tools/perl"
    assert Enum.at(hd(steps).args, 1) == "linux-x86_64"
    assert "no-apps" in hd(steps).args
    assert "no-module" in hd(steps).args
    assert List.last(steps).id == :native_install
    assert List.last(steps).args == ["--install", "/isolated/workspace/native-build"]

    sdk = Enum.find(steps, &(&1.id == :sdk_configure))
    assert Enum.at(steps, 3).id == :sdk_patch

    assert Enum.at(steps, 3).args == [
             "-DWOTEX_SDK_SOURCE=/isolated/workspace/sources/open62541/open62541-1.5.7",
             "-P",
             "/package/native/patch-sdk.cmake"
           ]

    for flag <- [
          "-DUA_ENABLE_DISCOVERY=ON",
          "-DUA_ENABLE_DISCOVERY_MULTICAST=OFF",
          "-DUA_ENABLE_METHODCALLS=ON",
          "-DUA_MULTITHREADING=0",
          "-DOPENSSL_USE_STATIC_LIBS=TRUE",
          "-DPKG_CONFIG_EXECUTABLE:FILEPATH=",
          "-DPKG_CONFIG_ARGN:STRING=",
          "-DPython3_EXECUTABLE=/tools/python",
          "-DOPENSSL_CRYPTO_LIBRARY=/isolated/workspace/openssl-prefix/lib/libcrypto.a"
        ] do
      assert flag in sdk.args
    end

    for step <- steps do
      assert step.timeout_ms == 600_000
      assert step.output_bytes == 16_777_216
      assert step.cleanup_ms == 1000
      assert {"LDFLAGS", nil} in step.env

      for name <- ~w(PKG_CONFIG PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR) do
        assert {name, nil} in step.env
      end

      assert {"CC", "/tools/cc"} in step.env
      refute step.executable in ["sh", "bash", "/bin/sh"]
    end
  end

  test "WOP-X02 supported CPU targets choose exact upstream Configure names" do
    for {target, expected} <- [
          {{:linux, :aarch64}, "linux-aarch64"},
          {{:darwin, :aarch64}, "darwin64-arm64-cc"}
        ] do
      assert {:ok, [configure | _]} = Recipe.new("/work", "/native", @tools, target)
      assert Enum.at(configure.args, 1) == expected
    end

    assert {:error, :unsupported_native_target} =
             Recipe.new("/work", "/native", @tools, {:windows, :x86_64})

    assert {:error, :unsupported_native_target} = Recipe.new("/work", "/native", @tools, nil)
  end

  test "WOP-X02 unknown tools and invalid paths cannot produce executable work" do
    for {workspace, native, tools} <- [
          {nil, "/native", @tools},
          {"/work", nil, @tools},
          {"/work", "/native", nil},
          {"relative", "/native", @tools},
          {"/work", "relative", @tools},
          {"/work", "/native", Map.delete(@tools, :cc)},
          {"/work", "/native", Map.put(@tools, :unknown, "/unknown")},
          {"/work", "/native", Map.put(@tools, :cc, nil)},
          {"/work", "/native", Map.put(@tools, :cc, "cc")},
          {"/work\nother", "/native", @tools}
        ] do
      assert {:error, :invalid_build_recipe} =
               Recipe.new(workspace, native, tools, {:linux, :x86_64})
    end
  end

  test "WOP-X02 whitespace remains inside a single argv path rather than shell text" do
    {:ok, [configure | _]} =
      Recipe.new("/work with spaces", "/package/native", @tools, {:linux, :x86_64})

    assert hd(configure.args) == "/work with spaces/sources/openssl/openssl-openssl-3.5.8/Configure"
    assert "--prefix=/work with spaces/openssl-prefix" in configure.args
  end
end
