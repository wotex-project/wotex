defmodule Wotex.Workspace.NativeTools do
  @moduledoc """
  Locates `clang-format` and `clang-tidy` and checks their version.

  Search order for a tool (`clang-format` or `clang-tidy`):

    1. the executable named by `CLANG_FORMAT` or `CLANG_TIDY`, when set;
    2. `clang-format` on `PATH`, then the versioned names Debian and Ubuntu
       install (`clang-format-23`, `clang-format-22`, ...);
    3. the Homebrew LLVM prefix (`/opt/homebrew/opt/llvm/bin`,
       `/usr/local/opt/llvm/bin`) and `/usr/lib/llvm-<major>/bin`.

  The first candidate whose major version is at least `minimum_major/0` is
  used. clang-format 22 and 23 (the version CI pins and the configuration
  was measured with) format every first-party source identically; 21
  differs on one construct, 20 on several, and 18 and 19 cannot read the
  configuration. A missing or too old tool fails with an install hint.

  `compilers/2` finds the C and C++ compilers of the same LLVM for the
  benchmarks (`mix native.bench`): `clang` and `clang++` in the directory
  of the clang-tidy found here, with links resolved, which is LLVM's own
  `bin` directory (a Homebrew cellar or `/usr/lib/llvm-<major>/bin`).
  """

  @minimum_major 22
  @newest_major 40
  @prefixes ["/opt/homebrew/opt/llvm/bin", "/usr/local/opt/llvm/bin"]

  @type tool :: :clang_format | :clang_tidy

  @type found :: %{tool: tool(), path: Path.t(), version: String.t(), major: pos_integer()}

  @typedoc "The C and C++ compilers of an LLVM installation and the C++ compiler's version line."
  @type compilers :: %{cc: Path.t(), cxx: Path.t(), version: String.t()}

  @typedoc """
  Replaceable effects (tests): `env` reads a variable, `find` resolves a
  name on `PATH`, `exists?` tests a path and `version` returns the
  `--version` output of an executable.
  """
  @type option ::
          {:env, (String.t() -> String.t() | nil)}
          | {:find, (String.t() -> Path.t() | nil)}
          | {:exists?, (Path.t() -> boolean())}
          | {:version, (Path.t() -> {:ok, String.t()} | :error)}

  @doc "The minimum supported LLVM major version."
  @spec minimum_major() :: pos_integer()
  def minimum_major, do: @minimum_major

  @doc "The executable name of `tool`."
  @spec name(tool()) :: String.t()
  def name(:clang_format), do: "clang-format"
  def name(:clang_tidy), do: "clang-tidy"

  @doc "The environment variable that names `tool` explicitly."
  @spec variable(tool()) :: String.t()
  def variable(:clang_format), do: "CLANG_FORMAT"
  def variable(:clang_tidy), do: "CLANG_TIDY"

  @doc "Finds `tool`; see the module documentation for the search order."
  @spec find(tool(), [option()]) :: {:ok, found()} | {:error, String.t()}
  def find(tool, opts \\ []) do
    env = Keyword.get(opts, :env, &System.get_env/1)
    version = Keyword.get(opts, :version, &version_output/1)

    find = Keyword.get(opts, :find, &System.find_executable/1)
    exists? = Keyword.get(opts, :exists?, &File.regular?/1)

    result =
      Enum.reduce_while(candidates(tool, env, find, exists?), [], fn path, seen ->
        case identify(tool, path, version) do
          {:ok, %{major: major} = found} when major >= @minimum_major -> {:halt, {:ok, found}}
          {:ok, found} -> {:cont, [found | seen]}
          :error -> {:cont, seen}
        end
      end)

    case result do
      {:ok, found} -> {:ok, found}
      seen -> {:error, missing_message(tool, Enum.reverse(seen))}
    end
  end

  @doc """
  The candidate paths for `tool`, in search order and without duplicates.
  """
  @spec candidates(
          tool(),
          (String.t() -> String.t() | nil),
          (String.t() -> Path.t() | nil),
          (Path.t() -> boolean())
        ) ::
          [Path.t()]
  def candidates(tool, env, find, exists?) do
    name = name(tool)
    majors = @newest_major..@minimum_major//-1

    explicit =
      case env.(variable(tool)) do
        value when value in [nil, ""] -> []
        value -> [find.(value) || value]
      end

    on_path = [find.(name) | Enum.map(majors, &find.("#{name}-#{&1}"))]

    prefixed =
      Enum.map(@prefixes, &Path.join(&1, name)) ++
        Enum.map(majors, &"/usr/lib/llvm-#{&1}/bin/#{name}")

    (explicit ++ Enum.reject(on_path, &is_nil/1) ++ Enum.filter(prefixed, exists?))
    |> Enum.uniq()
  end

  @doc """
  Parses the version from `--version` output, for example `Ubuntu
  clang-format version 18.1.3 (1ubuntu1)` or `LLVM version 23.1.1`.
  """
  @spec parse_version(String.t()) :: {:ok, String.t(), pos_integer()} | :error
  def parse_version(output) do
    case Regex.run(~r/(?:clang-format|LLVM) version (\d+)(\.\d+(?:\.\d+)?)?/, output) do
      [_, major, rest] -> {:ok, major <> rest, String.to_integer(major)}
      [_, major] -> {:ok, major, String.to_integer(major)}
      nil -> :error
    end
  end

  @doc "The install hint shown when `tool` is missing or too old."
  @spec install_hint(tool()) :: String.t()
  def install_hint(tool) do
    "install LLVM #{@minimum_major} or later: `brew install llvm` on macOS; on Debian or Ubuntu " <>
      "`apt install #{name(tool)}` when the distribution ships #{@minimum_major}+, else " <>
      "`apt install #{name(tool)}-23` from https://apt.llvm.org; or set #{variable(tool)} to the executable"
  end

  @doc """
  The `clang` and `clang++` beside `found` (a clang-tidy or clang-format
  from `find/2`), with the first line of `clang++ --version`. `exists?` and
  `version` replace the file and process checks in tests.
  """
  @spec compilers(found(), [option()]) :: {:ok, compilers()} | {:error, String.t()}
  def compilers(%{path: path, major: major}, opts \\ []) do
    exists? = Keyword.get(opts, :exists?, &File.regular?/1)
    version = Keyword.get(opts, :version, &version_output/1)
    dir = Path.dirname(real_path(path))
    cc = Path.join(dir, "clang")
    cxx = Path.join(dir, "clang++")

    with true <- exists?.(cc) and exists?.(cxx),
         {:ok, output} <- version.(cxx) do
      [line | _] = String.split(output, "\n")
      {:ok, %{cc: cc, cxx: cxx, version: String.trim(line)}}
    else
      _ ->
        {:error,
         "clang and clang++ not found in #{dir}, beside #{Path.basename(path)} #{major}; " <>
           "install the compiler of the same LLVM: `brew install llvm` on macOS, " <>
           "`apt install clang-#{major}` from https://apt.llvm.org on Debian or Ubuntu"}
    end
  end

  defp real_path(path) do
    case File.read_link(path) do
      {:ok, target} -> real_path(Path.expand(target, Path.dirname(path)))
      {:error, _} -> path
    end
  end

  defp identify(tool, path, version) do
    with {:ok, output} <- version.(path),
         {:ok, text, major} <- parse_version(output) do
      {:ok, %{tool: tool, path: path, version: text, major: major}}
    else
      _ -> :error
    end
  end

  defp version_output(path) do
    case System.cmd(path, ["--version"], env: [{"LC_ALL", "C"}], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      _ -> :error
    end
  rescue
    _ in [ErlangError, ArgumentError] -> :error
  end

  defp missing_message(tool, []), do: "#{name(tool)} not found; #{install_hint(tool)}"

  defp missing_message(tool, seen) do
    found = Enum.map_join(seen, ", ", &"#{&1.version} at #{&1.path}")
    "#{name(tool)} #{@minimum_major} or later not found (found #{found}); #{install_hint(tool)}"
  end
end
