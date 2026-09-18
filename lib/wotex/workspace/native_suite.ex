defmodule Wotex.Workspace.NativeSuite do
  @moduledoc """
  One entry of a package's `native_check` list in `tooling/packages.yaml`:
  how clang-tidy obtains compile commands for the package's first-party C
  and C++ sources and how its native tests run.

      native_check:
        - suite: sdk                      # name, unique within the package
          requires: [linux]               # host requirements: linux, docker
          build: wotex.opcua.native.build # package task run with --workspace {workspace}
          prepare:                        # commands run after the build
            - [cmake, -S, "{package}/priv/native", -B, "{scratch}/db", ...]
          compile_commands: ["{scratch}/db/compile_commands.json"]
          compile:                        # compile commands for files not in a database
            - files: ["test/native/*.c"]
              flags: [-std=c11, "-I{package}/priv/native"]
          test:                           # the package's native tests
            - [ctest, --test-dir, "{workspace}/native-build", --output-on-failure]

  A command is an argument list, or a mapping with `run` (the list) and the
  optional `env` (a mapping), `cd` (a directory) and `stdout` (a file that
  receives standard output). Commands run in the package directory unless
  `cd` says otherwise.

  `container` runs a suite's `prepare` and `test` commands and clang-tidy in
  a container, for a build whose compile commands name paths inside the
  container that built it (the suite must require `docker`):

      container:
        dockerfile: tooling/native/docker/matter-sdk.Dockerfile  # image source (repository-relative)
        platform: linux/amd64                                    # optional
        volumes:                                                 # HOST:CONTAINER, mounted read-only
          - "{workspace}:/work"
          - "{package}:/src"

  The container sees the volumes and the suite's scratch directory (at its
  host path), all read-only, and has no network; a command's `stdout` file
  is written on the host. Compile commands are mapped back to package files
  through the volumes (`Wotex.Workspace.NativeContainer`).

  Strings may contain placeholders: `{package}` (the absolute package
  directory), `{root}` (the repository root), `{workspace}` (the `build`
  task's workspace, only when `build` is set) and `{scratch}` (a directory
  emptied before `prepare`). A `compile` flag of the form `pkg-config:NAME`
  expands to the output of `pkg-config --cflags NAME`.
  """

  @requirements ~w(linux docker)
  @placeholders ~w(package root workspace scratch)

  @typedoc "A command: arguments, environment, working directory and optional stdout file."
  @type command :: %{
          run: [String.t()],
          env: [{String.t(), String.t()}],
          cd: String.t() | nil,
          stdout: String.t() | nil
        }

  @typedoc "Compile flags for the package files matching `files` (globs relative to the package)."
  @type compile :: %{files: [String.t()], flags: [String.t()]}

  @typedoc """
  The container of a suite: the repository-relative Dockerfile of its image,
  the optional platform and the `{host, container}` volume pairs.
  """
  @type container :: %{
          dockerfile: String.t(),
          platform: String.t() | nil,
          volumes: [{String.t(), String.t()}]
        }

  @type t :: %__MODULE__{
          name: String.t(),
          requires: [String.t()],
          build: String.t() | nil,
          prepare: [command()],
          compile_commands: [String.t()],
          compile: [compile()],
          test: [command()],
          container: container() | nil
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    requires: [],
    build: nil,
    prepare: [],
    compile_commands: [],
    compile: [],
    test: [],
    container: nil
  ]

  @doc "The host requirements a suite may declare."
  @spec requirements() :: [String.t()]
  def requirements, do: @requirements

  @doc """
  Parses the `native_check` value of package `package` (a list of suites,
  or `nil`).
  """
  @spec parse_all(String.t(), term()) :: {:ok, [t()]} | {:error, String.t()}
  def parse_all(_package, nil), do: {:ok, []}

  def parse_all(package, suites) when is_list(suites) do
    with {:ok, parsed} <- collect(suites, &parse(package, &1)), do: check_unique(package, parsed)
  end

  def parse_all(package, _other), do: {:error, "package #{package}: native_check must be a list"}

  @doc "Parses one suite mapping."
  @spec parse(String.t(), term()) :: {:ok, t()} | {:error, String.t()}
  def parse(package, %{"suite" => name} = entry) when is_binary(name) and name != "" do
    where = "package #{package}, native_check suite #{name}"
    known = ~w(suite requires build prepare compile_commands compile test container)

    with :ok <- known_keys(where, entry, known),
         {:ok, requires} <- requirements(where, Map.get(entry, "requires", [])),
         {:ok, build} <- build(where, Map.get(entry, "build")),
         {:ok, prepare} <- commands(where, "prepare", Map.get(entry, "prepare", [])),
         {:ok, databases} <-
           strings(where, "compile_commands", Map.get(entry, "compile_commands", [])),
         {:ok, compile} <- compile(where, Map.get(entry, "compile", [])),
         {:ok, test} <- commands(where, "test", Map.get(entry, "test", [])),
         {:ok, container} <- container(where, requires, Map.get(entry, "container")),
         suite = %__MODULE__{
           name: name,
           requires: requires,
           build: build,
           prepare: prepare,
           compile_commands: databases,
           compile: compile,
           test: test,
           container: container
         },
         :ok <- check_placeholders(where, suite) do
      {:ok, suite}
    end
  end

  def parse(package, _entry),
    do: {:error, "package #{package}: every native_check entry needs a suite name"}

  @doc """
  Replaces the placeholders in `text`. `values` maps placeholder names
  (`"package"`, `"root"`, `"workspace"`, `"scratch"`) to paths.
  """
  @spec expand(String.t(), %{String.t() => String.t()}) :: String.t()
  def expand(text, values) do
    Regex.replace(~r/\{([a-z]+)\}/, text, fn whole, name -> Map.get(values, name, whole) end)
  end

  @doc "Expands every string of `command`."
  @spec expand_command(command(), %{String.t() => String.t()}) :: command()
  def expand_command(command, values) do
    %{
      run: Enum.map(command.run, &expand(&1, values)),
      env: Enum.map(command.env, fn {name, value} -> {name, expand(value, values)} end),
      cd: command.cd && expand(command.cd, values),
      stdout: command.stdout && expand(command.stdout, values)
    }
  end

  # Parsing

  defp known_keys(where, entry, known) do
    case Map.keys(entry) -- known do
      [] -> :ok
      unknown -> {:error, "#{where}: unknown key(s) #{Enum.join(Enum.sort(unknown), ", ")}"}
    end
  end

  defp requirements(where, list) do
    with {:ok, list} <- strings(where, "requires", list) do
      case list -- @requirements do
        [] -> {:ok, list}
        unknown -> {:error, "#{where}: unknown requirement(s) #{Enum.join(unknown, ", ")}"}
      end
    end
  end

  defp build(_where, nil), do: {:ok, nil}
  defp build(_where, task) when is_binary(task) and task != "", do: {:ok, task}
  defp build(where, _task), do: {:error, "#{where}: build must be a task name"}

  defp strings(where, key, list) when is_list(list) do
    if Enum.all?(list, &(is_binary(&1) and &1 != "")),
      do: {:ok, list},
      else: {:error, "#{where}: #{key} must be a list of strings"}
  end

  defp strings(where, key, _other), do: {:error, "#{where}: #{key} must be a list of strings"}

  defp commands(where, key, list) when is_list(list),
    do: collect(list, &command(where, key, &1))

  defp commands(where, key, _other), do: {:error, "#{where}: #{key} must be a list of commands"}

  defp command(where, key, run) when is_list(run), do: command(where, key, %{"run" => run})

  defp command(where, key, %{"run" => run} = entry) do
    with :ok <- known_keys("#{where}, #{key}", entry, ~w(run env cd stdout)),
         {:ok, [_ | _] = run} <- strings(where, key, run),
         {:ok, env} <- env(where, key, Map.get(entry, "env", %{})),
         {:ok, cd} <- optional_string(where, key, "cd", Map.get(entry, "cd")),
         {:ok, stdout} <- optional_string(where, key, "stdout", Map.get(entry, "stdout")) do
      {:ok, %{run: run, env: env, cd: cd, stdout: stdout}}
    else
      {:ok, []} -> {:error, "#{where}: #{key} has an empty command"}
      error -> error
    end
  end

  defp command(where, key, _other), do: {:error, "#{where}: #{key} entries must be commands"}

  defp env(where, key, map) when is_map(map) do
    if Enum.all?(map, fn {name, value} -> is_binary(name) and is_binary(value) end),
      do: {:ok, Enum.sort(map)},
      else: {:error, "#{where}: #{key} env must map names to strings"}
  end

  defp env(where, key, _other), do: {:error, "#{where}: #{key} env must be a mapping"}

  defp optional_string(_where, _key, _field, nil), do: {:ok, nil}

  defp optional_string(_where, _key, _field, value) when is_binary(value) and value != "",
    do: {:ok, value}

  defp optional_string(where, key, field, _value),
    do: {:error, "#{where}: #{key} #{field} must be a string"}

  defp container(_where, _requires, nil), do: {:ok, nil}

  defp container(where, requires, %{"dockerfile" => dockerfile} = entry) do
    where = "#{where}, container"

    with :ok <- known_keys(where, entry, ~w(dockerfile platform volumes)),
         :ok <- require_docker(where, requires),
         {:ok, dockerfile} <- optional_string(where, "container", "dockerfile", dockerfile),
         {:ok, platform} <- optional_string(where, "container", "platform", entry["platform"]),
         {:ok, volumes} <- strings(where, "volumes", Map.get(entry, "volumes", [])),
         {:ok, volumes} <- collect(volumes, &volume(where, &1)) do
      {:ok, %{dockerfile: dockerfile, platform: platform, volumes: volumes}}
    end
  end

  defp container(where, _requires, _other),
    do: {:error, "#{where}: container must be a mapping with a dockerfile"}

  defp require_docker(where, requires) do
    if "docker" in requires,
      do: :ok,
      else: {:error, "#{where} needs requires: [docker]"}
  end

  defp volume(where, text) do
    case String.split(text, ":") do
      [host, "/" <> _ = container] when host != "" ->
        {:ok, {host, String.trim_trailing(container, "/")}}

      _other ->
        {:error, "#{where}: volume #{inspect(text)} must be HOST:/absolute/container/path"}
    end
  end

  defp compile(where, list) when is_list(list), do: collect(list, &compile_rule(where, &1))
  defp compile(where, _other), do: {:error, "#{where}: compile must be a list"}

  defp compile_rule(where, %{"files" => files, "flags" => flags} = entry) do
    with :ok <- known_keys("#{where}, compile", entry, ~w(files flags)),
         {:ok, [_ | _] = files} <- strings(where, "compile files", files),
         {:ok, flags} <- strings(where, "compile flags", flags) do
      {:ok, %{files: files, flags: flags}}
    else
      {:ok, []} -> {:error, "#{where}: compile files must not be empty"}
      error -> error
    end
  end

  defp compile_rule(where, _entry), do: {:error, "#{where}: compile entries need files and flags"}

  # Maps `fun` over `list` and stops at the first error.
  defp collect(list, fun) do
    list
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case fun.(entry) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> reverse_collected()
  end

  defp reverse_collected({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_collected(error), do: error

  defp check_placeholders(where, suite) do
    volumes = if suite.container, do: Enum.map(suite.container.volumes, &elem(&1, 0)), else: []

    strings =
      suite.compile_commands ++
        volumes ++
        Enum.flat_map(suite.compile, & &1.flags) ++
        Enum.flat_map(suite.prepare ++ suite.test, &command_strings/1)

    used =
      strings
      |> Enum.flat_map(&Regex.scan(~r/\{([a-z]+)\}/, &1, capture: :all_but_first))
      |> List.flatten()

    cond do
      (unknown = Enum.uniq(used) -- @placeholders) != [] ->
        {:error, "#{where}: unknown placeholder(s) #{Enum.map_join(unknown, ", ", &"{#{&1}}")}"}

      "workspace" in used and is_nil(suite.build) ->
        {:error, "#{where}: {workspace} needs a build task"}

      true ->
        :ok
    end
  end

  defp command_strings(command) do
    command.run ++
      Enum.map(command.env, &elem(&1, 1)) ++ Enum.reject([command.cd, command.stdout], &is_nil/1)
  end

  defp check_unique(package, suites) do
    names = Enum.map(suites, & &1.name)

    case names -- Enum.uniq(names) do
      [] ->
        {:ok, suites}

      [duplicate | _rest] ->
        {:error, "package #{package}: duplicate native_check suite #{duplicate}"}
    end
  end
end
