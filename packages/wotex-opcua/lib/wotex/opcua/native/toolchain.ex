defmodule Wotex.OPCUA.Native.Toolchain do
  @moduledoc """
  Identifies host executables for an explicitly requested native build.

  `resolve/0` locates the finite compiler/build/download tool set and records each
  absolute executable path and SHA-256. Resolution occurs only on invocation;
  dependency loading does not search PATH or inspect the filesystem. Missing
  tools, unresolved link chains and unsupported OS/CPU tuples are errors.

  `identify/2` also accepts an explicit tool map for an isolated build environment.
  `version_steps/2` supplies bounded version probes for the command guardian.
  Version outputs, OS details and executable hashes are separate receipt fields;
  a successful tool probe is not SDK or protocol acceptance evidence.
  """

  alias Wotex.OPCUA.Native.Workspace

  @names %{
    cc: "cc",
    cmake: "cmake",
    ctest: "ctest",
    make: "make",
    perl: "perl",
    python: "python3",
    ar: "ar",
    ranlib: "ranlib",
    curl: "curl",
    linker: "ld"
  }
  @recipe [:cc, :cmake, :ctest, :make, :perl, :python, :ar, :ranlib]

  @typedoc "Explicit tool paths, hashes, recipe subset and the supported build target."
  @type t :: %{paths: map(), hashes: map(), recipe: map(), target: tuple()}

  @doc "Finds and hashes the required tools for this explicitly selected host build."
  @spec resolve() :: {:ok, t()} | {:error, term()}
  def resolve do
    target = target(:os.type(), :erlang.system_info(:system_architecture))
    names = Map.put(@names, :system, if(elem(target, 0) == :darwin, do: "sw_vers", else: "ldd"))
    paths = Map.new(names, fn {key, name} -> {key, System.find_executable(name)} end)
    identify(paths, target)
  end

  @doc "Validates and hashes an explicit finite tool map without executing its tools."
  @spec identify(term(), term()) :: {:ok, t()} | {:error, term()}
  def identify(paths, target) when is_map(paths) do
    cond do
      target not in [{:linux, :x86_64}, {:linux, :aarch64}, {:darwin, :aarch64}] ->
        {:error, :unsupported_native_target}

      MapSet.new(Map.keys(paths)) != MapSet.new([:system | Map.keys(@names)]) ->
        {:error, :invalid_native_toolchain}

      true ->
        identify_paths(paths, target)
    end
  end

  def identify(_, _), do: {:error, :invalid_native_toolchain}

  @doc "Returns guarded version probes for the identified tools and system libraries."
  @spec version_steps(t(), String.t()) :: [Wotex.OPCUA.Native.Recipe.step()]
  def version_steps(%{paths: paths, target: target}, directory) do
    versions = [
      cc: ["--version"],
      cmake: ["--version"],
      ctest: ["--version"],
      make: ["--version"],
      perl: ["--version"],
      python: ["--version"],
      curl: ["--disable", "--version"],
      linker: if(elem(target, 0) == :darwin, do: ["-v"], else: ["--version"]),
      system: if(elem(target, 0) == :darwin, do: [], else: ["--version"])
    ]

    Enum.map(versions, fn {key, args} ->
      %{
        id: key,
        executable: Map.fetch!(paths, key),
        args: args,
        cwd: directory,
        env: [{"PATH", "/usr/bin:/bin"}, {"LC_ALL", "C"}],
        timeout_ms: 5000,
        output_bytes: 65_536,
        cleanup_ms: 1000
      }
    end)
  end

  defp target({:unix, :darwin}, architecture), do: {:darwin, cpu(architecture)}
  defp target({:unix, :linux}, architecture), do: {:linux, cpu(architecture)}
  defp target(_, _), do: {:unsupported, :unsupported}

  defp cpu(architecture) do
    case List.to_string(architecture) do
      "aarch64" <> _ -> :aarch64
      "arm64" <> _ -> :aarch64
      "x86_64" <> _ -> :x86_64
      _ -> :unsupported
    end
  end

  defp identify_paths(paths, target) do
    result =
      Enum.reduce_while(paths, {:ok, %{}, %{}}, fn {key, path}, {:ok, resolved, hashes} ->
        with {:ok, executable} <- resolve_link(path, 16),
             {:ok, digest} <- Workspace.digest(executable),
             {:ok, %{mode: mode}} when Bitwise.band(mode, 0o111) != 0 <- File.stat(executable) do
          {:cont, {:ok, Map.put(resolved, key, executable), Map.put(hashes, key, digest)}}
        else
          _ -> {:halt, {:error, {:missing_native_tool, key}}}
        end
      end)

    case result do
      {:ok, resolved, hashes} ->
        {:ok,
         %{paths: resolved, hashes: hashes, recipe: Map.take(resolved, @recipe), target: target}}

      error ->
        error
    end
  end

  defp resolve_link(path, remaining) when is_binary(path) and remaining > 0 do
    if Path.type(path) == :absolute do
      case File.lstat(path) do
        {:ok, %{type: :regular}} ->
          {:ok, path}

        {:ok, %{type: :symlink}} ->
          with {:ok, destination} <- File.read_link(path),
               do: resolve_link(Path.expand(destination, Path.dirname(path)), remaining - 1)

        _ ->
          {:error, :invalid_native_tool}
      end
    else
      {:error, :invalid_native_tool}
    end
  end

  defp resolve_link(_, _), do: {:error, :invalid_native_tool}
end
