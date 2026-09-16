defmodule Wotex.CoAP.Native.Toolchain do
  @moduledoc """
  Resolves and fingerprints the host tools for an explicit native build.

  Resolution happens once when the build task is invoked. `CC`, `CMAKE` and
  `OPENSSL_ROOT_DIR` select caller-owned tools when present; otherwise fixed
  executable names are resolved on the caller's PATH. Every executable link is
  resolved to an ordinary executable file and hashed. Linux x86-64/AArch64 and
  macOS AArch64 are the supported targets.
  """

  alias Wotex.CoAP.Native.Workspace

  @fixed %{
    curl: "curl",
    patch: "patch",
    pkg_config: "pkg-config"
  }
  @keys [:cc, :cmake, :curl, :openssl, :patch, :pkg_config, :system]

  @typedoc "Resolved paths, executable hashes, OpenSSL root and supported target."
  @type t :: %{
          paths: %{required(atom()) => String.t()},
          hashes: %{required(atom()) => String.t()},
          openssl_root: String.t(),
          target: {:darwin | :linux, :aarch64 | :x86_64}
        }

  @doc "Resolves the caller-selected native build toolchain without running it."
  @spec resolve() :: {:ok, t()} | {:error, term()}
  def resolve do
    target = target(:os.type(), :erlang.system_info(:system_architecture))

    with :ok <- supported_target(target),
         {:ok, cc} <- selected("CC", "cc"),
         {:ok, cmake} <- selected("CMAKE", "cmake"),
         {:ok, fixed} <- fixed(target),
         {:ok, openssl, root} <- openssl() do
      fixed
      |> Map.merge(%{cc: cc, cmake: cmake, openssl: openssl})
      |> identify(root, target)
    end
  end

  @doc "Validates and hashes an explicit tool set for isolated build verification."
  @spec identify(term(), term(), term()) :: {:ok, t()} | {:error, term()}
  def identify(paths, openssl_root, target) when is_map(paths) and is_binary(openssl_root) do
    cond do
      supported_target(target) != :ok ->
        {:error, :unsupported_native_target}

      MapSet.new(Map.keys(paths)) != MapSet.new(@keys) or
        Path.type(openssl_root) != :absolute or not File.dir?(openssl_root) ->
        {:error, :invalid_native_toolchain}

      true ->
        identify_paths(paths, openssl_root, target)
    end
  end

  def identify(_, _, _), do: {:error, :invalid_native_toolchain}

  @doc false
  @spec target(term(), term()) ::
          {:darwin, :aarch64 | :x86_64 | :unsupported}
          | {:linux, :aarch64 | :x86_64 | :unsupported}
          | {:unsupported, :unsupported}
  def target({:unix, :darwin}, architecture), do: {:darwin, cpu(architecture)}
  def target({:unix, :linux}, architecture), do: {:linux, cpu(architecture)}
  def target(_, _), do: {:unsupported, :unsupported}

  @doc "Returns the bounded version probes recorded by the native manifest."
  @spec version_commands(t()) :: [{atom(), String.t(), [String.t()]}]
  def version_commands(%{paths: paths, target: target}) do
    [
      {:cc, paths.cc, ["--version"]},
      {:cmake, paths.cmake, ["--version"]},
      {:openssl, paths.openssl, ["version", "-a"]},
      {:curl, paths.curl, ["--disable", "--version"]},
      {:patch, paths.patch, ["--version"]},
      {:pkg_config, paths.pkg_config, ["--version"]},
      {:system, paths.system, if(elem(target, 0) == :darwin, do: [], else: ["--version"])}
    ]
  end

  defp selected(variable, fallback) do
    case System.get_env(variable) do
      nil -> locate(fallback)
      "" -> {:error, {:invalid_native_tool, variable}}
      value -> locate(value)
    end
  end

  defp fixed(target) do
    system = if elem(target, 0) == :darwin, do: "otool", else: "ldd"

    Enum.reduce_while(Map.put(@fixed, :system, system), {:ok, %{}}, fn {key, name}, {:ok, paths} ->
      case locate(name) do
        {:ok, path} -> {:cont, {:ok, Map.put(paths, key, path)}}
        _ -> {:halt, {:error, {:missing_native_tool, key}}}
      end
    end)
  end

  defp openssl do
    case System.get_env("OPENSSL_ROOT_DIR") do
      nil ->
        with {:ok, executable} <- locate("openssl") do
          root = Path.dirname(Path.dirname(executable))
          {:ok, executable, root}
        end

      root when is_binary(root) ->
        executable = Path.join([root, "bin", "openssl"])

        if Path.type(root) == :absolute and File.dir?(root),
          do: with({:ok, path} <- locate(executable), do: {:ok, path, root}),
          else: {:error, :invalid_openssl_root}
    end
  end

  defp locate(name) when is_binary(name) do
    path = if String.contains?(name, "/"), do: name, else: System.find_executable(name)
    resolve_link(path, 16)
  end

  defp resolve_link(path, remaining) when is_binary(path) and remaining > 0 do
    if Path.type(path) == :absolute do
      case File.lstat(path) do
        {:ok, %{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 ->
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

  defp identify_paths(paths, openssl_root, target) do
    result =
      Enum.reduce_while(paths, {:ok, %{}, %{}}, fn {key, path}, {:ok, resolved, hashes} ->
        with {:ok, executable} <- resolve_link(path, 16),
             {:ok, digest} <- Workspace.digest(executable) do
          {:cont, {:ok, Map.put(resolved, key, executable), Map.put(hashes, key, digest)}}
        else
          _ -> {:halt, {:error, {:missing_native_tool, key}}}
        end
      end)

    case result do
      {:ok, resolved, hashes} ->
        {:ok, %{paths: resolved, hashes: hashes, openssl_root: openssl_root, target: target}}

      error ->
        error
    end
  end

  defp supported_target(target) do
    if target in [{:linux, :x86_64}, {:linux, :aarch64}, {:darwin, :aarch64}],
      do: :ok,
      else: {:error, :unsupported_native_target}
  end

  defp cpu(architecture) do
    case List.to_string(architecture) do
      "aarch64" <> _ -> :aarch64
      "arm64" <> _ -> :aarch64
      "x86_64" <> _ -> :x86_64
      _ -> :unsupported
    end
  end
end
