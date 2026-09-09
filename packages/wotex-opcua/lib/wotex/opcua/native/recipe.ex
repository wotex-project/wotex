defmodule Wotex.OPCUA.Native.Recipe do
  @moduledoc """
  Constructs the explicit command sequence for a pinned native client build.

  `new/4` accepts an absolute workspace, the packaged native source directory,
  an identified tool map and a supported OS/CPU tuple. It returns separate
  executable/argument vectors with their working directories and environment
  overrides. No command runs and no directory is created by this module.

  The build owner verifies source and tool digests, owns the workspace and runs
  each step with finite time/output/cleanup limits. Commands use only workspace
  SDK/OpenSSL prefixes; ambient compiler, linker, include and pkg-config settings
  are cleared. A recipe is not build evidence or a native connection capability.
  """

  alias Wotex.OPCUA.Native.Source

  @tools [:cc, :cmake, :ctest, :make, :perl, :python, :ar, :ranlib]
  @clear ~w(CFLAGS CXXFLAGS CPPFLAGS LDFLAGS LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH PKG_CONFIG_PATH CMAKE_PREFIX_PATH MAKEFLAGS MFLAGS)
  @targets %{
    {:linux, :x86_64} => "linux-x86_64",
    {:linux, :aarch64} => "linux-aarch64",
    {:darwin, :aarch64} => "darwin64-arm64-cc"
  }

  @typedoc "One bounded command executed by the explicit build owner."
  @type step :: %{
          id: atom(),
          executable: String.t(),
          args: [String.t()],
          cwd: String.t(),
          env: [{String.t(), String.t() | nil}],
          timeout_ms: pos_integer(),
          output_bytes: pos_integer(),
          cleanup_ms: pos_integer()
        }

  @doc "Returns the exact native build steps, or rejects an incomplete configuration."
  @spec new(term(), term(), term(), term()) ::
          {:ok, [step()]} | {:error, :invalid_build_recipe | :unsupported_native_target}
  def new(workspace, native, tools, target)
      when is_binary(workspace) and is_binary(native) and is_map(tools) do
    cond do
      not valid_paths?(workspace, native, tools) ->
        {:error, :invalid_build_recipe}

      not Map.has_key?(@targets, target) ->
        {:error, :unsupported_native_target}

      true ->
        {:ok, steps(workspace, native, tools, Map.fetch!(@targets, target))}
    end
  end

  def new(_, _, _, _), do: {:error, :invalid_build_recipe}

  defp valid_paths?(workspace, native, tools) do
    MapSet.new(Map.keys(tools)) == MapSet.new(@tools) and
      Enum.all?([workspace, native | Map.values(tools)], &absolute?/1)
  end

  defp absolute?(path) when is_binary(path) do
    byte_size(path) in 1..4096 and String.valid?(path) and Path.type(path) == :absolute and
      not String.contains?(path, [<<0>>, "\n", "\r"])
  end

  defp absolute?(_), do: false

  defp steps(workspace, native, tools, target) do
    {:ok, ssl} = Source.fetch(:openssl)
    {:ok, sdk} = Source.fetch(:open62541)
    ssl_source = Path.join([workspace, "sources", ssl.name, ssl.root])
    sdk_source = Path.join([workspace, "sources", sdk.name, sdk.root])
    ssl_prefix = Path.join(workspace, "openssl-prefix")
    sdk_prefix = Path.join(workspace, "sdk-prefix")
    sdk_build = Path.join(workspace, "sdk-build")
    native_build = Path.join(workspace, "native-build")
    env = environment(tools)

    configure = [
      Path.join(ssl_source, "Configure"),
      target,
      "no-shared",
      "no-tests",
      "no-apps",
      "no-module",
      "--prefix=" <> ssl_prefix,
      "--libdir=lib"
    ]

    sdk_flags = sdk_options(ssl_prefix, sdk_prefix, tools)

    native_flags = [
      "-DWOTEX_SDK_PREFIX=" <> sdk_prefix,
      "-DWOTEX_OPENSSL_PREFIX=" <> ssl_prefix,
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
      "-DCMAKE_C_COMPILER=" <> tools.cc,
      "-DCMAKE_MAKE_PROGRAM=" <> tools.make,
      "-DCMAKE_INSTALL_PREFIX=" <> Path.join(workspace, "output")
    ]

    [
      step(:openssl_configure, tools.perl, configure, ssl_source, env),
      step(:openssl_compile, tools.make, ["-j4"], ssl_source, env),
      step(:openssl_install, tools.make, ["install_sw"], ssl_source, env),
      step(:sdk_configure, tools.cmake, cmake(sdk_source, sdk_build, sdk_flags), workspace, env),
      step(:sdk_compile, tools.cmake, ["--build", sdk_build, "--parallel", "4"], workspace, env),
      step(:sdk_install, tools.cmake, ["--install", sdk_build], workspace, env),
      step(
        :native_configure,
        tools.cmake,
        cmake(native, native_build, native_flags),
        workspace,
        env
      ),
      step(
        :native_compile,
        tools.cmake,
        ["--build", native_build, "--parallel", "4"],
        workspace,
        env
      ),
      step(
        :native_test,
        tools.ctest,
        ["--test-dir", native_build, "--output-on-failure"],
        workspace,
        env
      ),
      step(:native_install, tools.cmake, ["--install", native_build], workspace, env)
    ]
  end

  defp sdk_options(ssl, prefix, tools) do
    [
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
      "-DCMAKE_C_COMPILER=" <> tools.cc,
      "-DCMAKE_MAKE_PROGRAM=" <> tools.make,
      "-DPython3_EXECUTABLE=" <> tools.python,
      "-DCMAKE_INSTALL_PREFIX=" <> prefix,
      "-DCMAKE_INSTALL_LIBDIR=lib",
      "-DBUILD_SHARED_LIBS=OFF",
      "-DUA_ENABLE_ENCRYPTION=OPENSSL",
      "-DUA_ENABLE_SUBSCRIPTIONS=ON",
      "-DUA_ENABLE_SUBSCRIPTIONS_EVENTS=OFF",
      "-DUA_ENABLE_PUBSUB=OFF",
      "-DUA_ENABLE_DISCOVERY=ON",
      "-DUA_ENABLE_DISCOVERY_MULTICAST=OFF",
      "-DUA_ENABLE_METHODCALLS=ON",
      "-DUA_NAMESPACE_ZERO=REDUCED",
      "-DUA_ENABLE_JSON_ENCODING=ON",
      "-DUA_MULTITHREADING=0",
      "-DUA_BUILD_EXAMPLES=OFF",
      "-DUA_BUILD_UNIT_TESTS=OFF",
      "-DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=TRUE",
      "-DOPENSSL_USE_STATIC_LIBS=TRUE",
      "-DOPENSSL_ROOT_DIR=" <> ssl,
      "-DOPENSSL_INCLUDE_DIR=" <> Path.join(ssl, "include"),
      "-DOPENSSL_SSL_LIBRARY=" <> Path.join(ssl, "lib/libssl.a"),
      "-DOPENSSL_CRYPTO_LIBRARY=" <> Path.join(ssl, "lib/libcrypto.a")
    ]
  end

  defp environment(tools) do
    path =
      tools
      |> Map.values()
      |> Enum.map(&Path.dirname/1)
      |> Kernel.++(["/usr/bin", "/bin"])
      |> Enum.uniq()
      |> Enum.join(":")

    Enum.map(@clear, &{&1, nil}) ++
      [
        {"CC", tools.cc},
        {"AR", tools.ar},
        {"RANLIB", tools.ranlib},
        {"LC_ALL", "C"},
        {"PATH", path}
      ]
  end

  defp cmake(source, build, flags), do: ["-S", source, "-B", build, "-G", "Unix Makefiles" | flags]

  defp step(id, executable, args, cwd, env) do
    %{
      id: id,
      executable: executable,
      args: args,
      cwd: cwd,
      env: env,
      timeout_ms: 600_000,
      output_bytes: 16_777_216,
      cleanup_ms: 1000
    }
  end
end
