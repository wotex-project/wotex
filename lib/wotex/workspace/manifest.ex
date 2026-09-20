defmodule Wotex.Workspace.Manifest do
  @moduledoc """
  The package manifest, `tooling/packages.yaml`.

  The manifest is the single source for the package dependency graph. Loading
  validates it: every `depends_on` entry names a manifest package and the
  graph has no cycle. Functions that take a manifest default to the
  repository's own; tests pass fixture manifests built with `from_map/2`.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.NativeBench
  alias Wotex.Workspace.NativeSuite

  defmodule NativeArtifactProfile do
    @moduledoc "An explicitly admitted package-owned native artifact descriptor."

    @type t :: %__MODULE__{profile: String.t(), descriptor: Path.t()}

    @enforce_keys [:profile, :descriptor]
    defstruct [:profile, :descriptor]
  end

  defmodule NativeArtifactTarget do
    @moduledoc "A target tuple admitted by the root native artifact inventory."

    @type t :: %__MODULE__{
            name: String.t(),
            operating_system: String.t(),
            architecture: String.t(),
            endianness: String.t(),
            libc: String.t(),
            abi: String.t(),
            toolchain: String.t(),
            system: String.t()
          }

    @enforce_keys [
      :name,
      :operating_system,
      :architecture,
      :endianness,
      :libc,
      :abi,
      :toolchain,
      :system
    ]
    defstruct @enforce_keys
  end

  defmodule NativeArtifactInput do
    @moduledoc "A content-bound toolchain or system identity and its repository inputs."

    @type t :: %__MODULE__{name: String.t(), identity: String.t(), inputs: [Path.t()]}

    @enforce_keys [:name, :identity]
    defstruct [:name, :identity, inputs: []]
  end

  defmodule NativeArtifactConfig do
    @moduledoc "Closed root configuration for native artifact planning."

    @type smoke_cell :: %{package: String.t(), profile: String.t(), target: String.t()}

    @type t :: %__MODULE__{
            schema_version: String.t(),
            matrix_limit: pos_integer(),
            max_slices: pos_integer(),
            targets: %{String.t() => NativeArtifactTarget.t()},
            toolchains: %{String.t() => NativeArtifactInput.t()},
            systems: %{String.t() => NativeArtifactInput.t()},
            smoke: [smoke_cell()]
          }

    @enforce_keys [:schema_version]
    defstruct schema_version: nil,
              matrix_limit: 64,
              max_slices: 16,
              targets: %{},
              toolchains: %{},
              systems: %{},
              smoke: []
  end

  defmodule Host do
    @moduledoc """
    One `hosts` entry of a package: an application inside the package
    directory with its own `mix.exs` and lock, such as a reference host that
    consumes the package. `path` is relative to the package directory and
    `env` is the environment its commands need (for example
    `MIX_TARGET=host`).
    """

    @type t :: %__MODULE__{path: Path.t(), env: [{String.t(), String.t()}]}

    @enforce_keys [:path]
    defstruct [:path, env: []]
  end

  defmodule Package do
    @moduledoc """
    One `packages.<name>` entry of the manifest.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            app: String.t(),
            depends_on: [String.t()],
            native: boolean(),
            native_task: String.t() | nil,
            software_task: String.t() | nil,
            native_check: [Wotex.Workspace.NativeSuite.t()],
            native_bench: [Wotex.Workspace.NativeBench.t()],
            native_artifacts: [Wotex.Workspace.Manifest.NativeArtifactProfile.t()],
            hosts: [Wotex.Workspace.Manifest.Host.t()]
          }

    @enforce_keys [:name, :app]
    defstruct [
      :name,
      :app,
      depends_on: [],
      native: false,
      native_task: nil,
      software_task: nil,
      native_check: [],
      native_bench: [],
      native_artifacts: [],
      hosts: []
    ]
  end

  @type lane :: %{elixir: String.t(), otp: String.t(), skip: [String.t()]}

  @type t :: %__MODULE__{
          path: Path.t() | nil,
          schema_version: String.t() | nil,
          lanes: %{String.t() => lane()},
          select_all_on: [String.t()],
          native_artifact: NativeArtifactConfig.t(),
          packages: %{String.t() => Package.t()},
          order: [String.t()]
        }

  defstruct path: nil,
            schema_version: nil,
            lanes: %{},
            select_all_on: [],
            native_artifact: nil,
            packages: %{},
            order: []

  @name_pattern ~r/^[a-z][a-z0-9-]*$/

  @doc "Path of the repository's manifest."
  @spec default_path() :: Path.t()
  def default_path, do: Path.join(Workspace.root(), "tooling/packages.yaml")

  @doc "Loads and validates a manifest file."
  @spec load(Path.t()) :: {:ok, t()} | {:error, String.t()}
  def load(path \\ default_path()) do
    case YamlElixir.read_from_file(path) do
      {:ok, map} when is_map(map) -> from_map(map, path)
      {:ok, _} -> {:error, "#{path}: the manifest must be a mapping"}
      {:error, error} -> {:error, "#{path}: #{Exception.message(error)}"}
    end
  end

  @doc "Loads a manifest file or raises."
  @spec load!(Path.t()) :: t()
  def load!(path \\ default_path()) do
    case load(path) do
      {:ok, manifest} -> manifest
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Builds and validates a manifest from a decoded YAML map (string keys).
  """
  @spec from_map(map(), Path.t() | nil) :: {:ok, t()} | {:error, String.t()}
  def from_map(map, path \\ nil) when is_map(map) do
    with {:ok, packages} <- parse_packages(Map.get(map, "packages")),
         :ok <- check_dependencies(packages),
         {:ok, order} <- topological_sort(packages),
         {:ok, lanes} <- parse_lanes(Map.get(map, "lanes", %{})),
         {:ok, globs} <- parse_globs(Map.get(map, "select_all_on", [])),
         {:ok, native_artifact} <-
           parse_native_artifact(Map.get(map, "native_artifact", %{}), packages) do
      {:ok,
       %__MODULE__{
         path: path,
         schema_version: Map.get(map, "schema_version"),
         lanes: lanes,
         select_all_on: globs,
         native_artifact: native_artifact,
         packages: packages,
         order: order
       }}
    else
      {:error, message} -> {:error, prefix(path, message)}
    end
  end

  @doc "All packages, sorted by name."
  @spec packages(t()) :: [Package.t()]
  def packages(%__MODULE__{} = manifest \\ load!()) do
    Enum.sort_by(Map.values(manifest.packages), & &1.name)
  end

  @doc "All package names, sorted."
  @spec names(t()) :: [String.t()]
  def names(%__MODULE__{} = manifest \\ load!()), do: Enum.sort(Map.keys(manifest.packages))

  @doc "Fetches a package by name."
  @spec fetch(String.t(), t()) :: {:ok, Package.t()} | :error
  def fetch(name, %__MODULE__{} = manifest \\ load!()), do: Map.fetch(manifest.packages, name)

  @doc "Fetches a package by name or raises."
  @spec fetch!(String.t(), t()) :: Package.t()
  def fetch!(name, %__MODULE__{} = manifest \\ load!()) do
    case fetch(name, manifest) do
      {:ok, package} -> package
      :error -> raise ArgumentError, "unknown package #{inspect(name)}"
    end
  end

  @doc "Whether the manifest names `name`."
  @spec package?(String.t(), t()) :: boolean()
  def package?(name, %__MODULE__{} = manifest \\ load!()), do: Map.has_key?(manifest.packages, name)

  @doc "Repository-relative path of a package directory: `packages/<name>`."
  @spec path(String.t(), t()) :: Path.t()
  def path(name, %__MODULE__{} = manifest \\ load!()) do
    _ = fetch!(name, manifest)
    "packages/#{name}"
  end

  @doc "Absolute path of a package directory below `root`."
  @spec absolute_path(String.t(), t(), Path.t()) :: Path.t()
  def absolute_path(name, %__MODULE__{} = manifest \\ load!(), root \\ Workspace.root()) do
    Path.join(root, path(name, manifest))
  end

  @doc "Packages that depend directly on `name`, sorted by name."
  @spec dependents(String.t(), t()) :: [String.t()]
  def dependents(name, %__MODULE__{} = manifest \\ load!()) do
    _ = fetch!(name, manifest)

    manifest.packages
    |> Map.values()
    |> Enum.filter(&(name in &1.depends_on))
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  @doc """
  Every package that depends on `name` directly or through other packages,
  in topological order. `name` itself is not included.
  """
  @spec transitive_dependents(String.t(), t()) :: [String.t()]
  def transitive_dependents(name, %__MODULE__{} = manifest \\ load!()) do
    _ = fetch!(name, manifest)
    closure = close_over(MapSet.new([name]), &dependents(&1, manifest))
    Enum.filter(manifest.order, &(&1 != name and MapSet.member?(closure, &1)))
  end

  @doc """
  Every package that `name` depends on directly or through other packages,
  in topological order. `name` itself is not included.
  """
  @spec transitive_dependencies(String.t(), t()) :: [String.t()]
  def transitive_dependencies(name, %__MODULE__{} = manifest \\ load!()) do
    _ = fetch!(name, manifest)
    closure = close_over(MapSet.new([name]), &fetch!(&1, manifest).depends_on)
    Enum.filter(manifest.order, &(&1 != name and MapSet.member?(closure, &1)))
  end

  @doc """
  All package names so that every package follows the packages it depends
  on. Ties are broken alphabetically, which makes the order deterministic.
  """
  @spec topological_order(t()) :: [String.t()]
  def topological_order(%__MODULE__{} = manifest \\ load!()), do: manifest.order

  @doc "Restricts `names` to the manifest's topological order."
  @spec in_order(Enumerable.t(), t()) :: [String.t()]
  def in_order(names, %__MODULE__{} = manifest \\ load!()) do
    set = MapSet.new(names)
    Enum.filter(manifest.order, &MapSet.member?(set, &1))
  end

  @doc "Packages with `native: true`, sorted by name."
  @spec native_packages(t()) :: [Package.t()]
  def native_packages(%__MODULE__{} = manifest \\ load!()) do
    Enum.filter(packages(manifest), & &1.native)
  end

  @doc "Toolchain lane `name`, if declared."
  @spec lane(String.t(), t()) :: {:ok, lane()} | :error
  def lane(name, %__MODULE__{} = manifest \\ load!()), do: Map.fetch(manifest.lanes, name)

  # Parsing

  defp parse_packages(nil), do: {:error, "missing packages"}

  defp parse_packages(packages) when is_map(packages) and map_size(packages) > 0 do
    packages
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, fn {name, entry}, {:ok, acc} ->
      case parse_package(name, entry) do
        {:ok, package} -> {:cont, {:ok, Map.put(acc, name, package)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp parse_packages(_), do: {:error, "packages must be a non-empty mapping"}

  defp parse_package(name, entry) when is_binary(name) and is_map(entry) do
    with :ok <- check_name(name),
         {:ok, app} <- parse_app(name, Map.get(entry, "app")),
         {:ok, depends_on} <- parse_depends_on(name, Map.get(entry, "depends_on", [])),
         {:ok, native} <- parse_boolean(name, "native", Map.get(entry, "native", false)),
         {:ok, native_task} <- parse_task(name, "native_task", Map.get(entry, "native_task")),
         {:ok, software_task} <-
           parse_task(name, "software_task", Map.get(entry, "software_task")),
         {:ok, native_check} <- NativeSuite.parse_all(name, Map.get(entry, "native_check")),
         {:ok, native_bench} <- NativeBench.parse_all(name, Map.get(entry, "native_bench")),
         {:ok, native_artifacts} <-
           parse_native_artifact_profiles(name, Map.get(entry, "native_artifacts", [])),
         {:ok, hosts} <- parse_hosts(name, Map.get(entry, "hosts", [])),
         package = %Package{
           name: name,
           app: app,
           depends_on: depends_on,
           native: native,
           native_task: native_task,
           software_task: software_task,
           native_check: native_check,
           native_bench: native_bench,
           native_artifacts: native_artifacts,
           hosts: hosts
         },
         :ok <- check_native_bench(package) do
      {:ok, package}
    end
  end

  defp parse_package(name, _), do: {:error, "package #{inspect(name)} must be a mapping"}

  # A benchmark belongs to a native package; the elixir kind runs after the
  # package's native_task, and the clang-tidy suite of a nanobench driver
  # must not take the name of a native_check suite.
  defp check_native_bench(%Package{native_bench: []}), do: :ok

  defp check_native_bench(%Package{native: false, name: name}),
    do: {:error, "package #{name}: native_bench needs native: true"}

  defp check_native_bench(%Package{} = package) do
    suites = MapSet.new(package.native_check, & &1.name)

    Enum.reduce_while(package.native_bench, :ok, fn bench, :ok ->
      where = "package #{package.name}, native_bench #{bench.id}"

      cond do
        bench.kind == :elixir and is_nil(package.native_task) ->
          {:halt, {:error, "#{where}: the elixir kind needs the package's native_task"}}

        MapSet.member?(suites, NativeBench.suite_name(bench)) ->
          {:halt,
           {:error,
            "#{where}: native_check suite #{NativeBench.suite_name(bench)} takes its clang-tidy suite name"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp check_name(name) do
    if Regex.match?(@name_pattern, name),
      do: :ok,
      else: {:error, "package name #{inspect(name)} is not lowercase-with-dashes"}
  end

  defp parse_app(_, app) when is_binary(app) and app != "" do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, app),
      do: {:ok, app},
      else: {:error, "app #{inspect(app)} is not a valid OTP application name"}
  end

  defp parse_app(name, _), do: {:error, "package #{name}: app is required"}

  defp parse_depends_on(name, list) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      {:ok, Enum.uniq(list)}
    else
      {:error, "package #{name}: depends_on must list package names"}
    end
  end

  defp parse_depends_on(name, _), do: {:error, "package #{name}: depends_on must be a list"}

  defp parse_boolean(_, _, value) when is_boolean(value), do: {:ok, value}
  defp parse_boolean(name, key, _), do: {:error, "package #{name}: #{key} must be a boolean"}

  defp parse_task(_, _, nil), do: {:ok, nil}
  defp parse_task(_, _, task) when is_binary(task) and task != "", do: {:ok, task}
  defp parse_task(name, key, _), do: {:error, "package #{name}: #{key} must be a task name"}

  defp parse_native_artifact_profiles(name, profiles) when is_list(profiles) do
    parsed = Enum.map(profiles, &parse_native_artifact_profile/1)

    cond do
      :error in parsed ->
        {:error,
         "package #{name}: every native_artifacts entry needs a lowercase profile and a relative descriptor path"}

      Enum.uniq_by(parsed, &elem(&1, 1).profile) != parsed ->
        {:error, "package #{name}: native_artifacts must not repeat a profile"}

      Enum.uniq_by(parsed, &elem(&1, 1).descriptor) != parsed ->
        {:error, "package #{name}: native_artifacts must not repeat a descriptor path"}

      true ->
        {:ok, Enum.map(parsed, &elem(&1, 1))}
    end
  end

  defp parse_native_artifact_profiles(name, _),
    do: {:error, "package #{name}: native_artifacts must be a list"}

  defp parse_native_artifact_profile(%{"profile" => profile, "descriptor" => descriptor} = entry)
       when is_binary(profile) and is_binary(descriptor) do
    with [] <- Map.keys(entry) -- ["profile", "descriptor"],
         true <- Regex.match?(@name_pattern, profile),
         true <- relative_inside?(descriptor) do
      {:ok, %NativeArtifactProfile{profile: profile, descriptor: descriptor}}
    else
      _ -> :error
    end
  end

  defp parse_native_artifact_profile(_), do: :error

  defp parse_native_artifact(config, _) when config == %{} do
    {:ok, %NativeArtifactConfig{schema_version: "1.0.0"}}
  end

  defp parse_native_artifact(%{"schema_version" => "1.0.0"} = config, packages) do
    allowed =
      ~w(schema_version matrix_limit max_slices targets toolchains systems smoke)

    with [] <- Map.keys(config) -- allowed,
         {:ok, matrix_limit} <- positive_integer(config, "matrix_limit", 64),
         {:ok, max_slices} <- positive_integer(config, "max_slices", 16),
         {:ok, toolchains} <- parse_native_inputs(config, "toolchains"),
         {:ok, systems} <- parse_native_inputs(config, "systems"),
         {:ok, targets} <-
           parse_native_targets(Map.get(config, "targets", %{}), toolchains, systems),
         {:ok, smoke} <- parse_native_smoke(Map.get(config, "smoke", []), packages, targets) do
      {:ok,
       %NativeArtifactConfig{
         schema_version: "1.0.0",
         matrix_limit: matrix_limit,
         max_slices: max_slices,
         targets: targets,
         toolchains: toolchains,
         systems: systems,
         smoke: smoke
       }}
    else
      [_ | _] = unknown ->
        {:error, "native_artifact has unknown fields: #{Enum.join(Enum.sort(unknown), ", ")}"}

      {:error, message} ->
        {:error, message}

      _ ->
        {:error, "native_artifact is invalid"}
    end
  end

  defp parse_native_artifact(%{"schema_version" => version}, _),
    do: {:error, "native_artifact schema_version #{inspect(version)} is unsupported"}

  defp parse_native_artifact(_, _),
    do: {:error, "native_artifact must be a mapping with schema_version 1.0.0"}

  defp positive_integer(map, key, default) do
    case Map.get(map, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, "native_artifact #{key} must be a positive integer"}
    end
  end

  defp parse_native_inputs(config, key) do
    case Map.get(config, key, %{}) do
      inputs when is_map(inputs) ->
        Enum.reduce_while(Enum.sort(inputs), {:ok, %{}}, fn {name, entry}, {:ok, acc} ->
          case parse_native_input(key, name, entry) do
            {:ok, input} -> {:cont, {:ok, Map.put(acc, name, input)}}
            {:error, message} -> {:halt, {:error, message}}
          end
        end)

      _ ->
        {:error, "native_artifact #{key} must be a mapping"}
    end
  end

  defp parse_native_input(kind, name, %{"identity" => identity} = entry)
       when is_binary(name) and is_binary(identity) and identity != "" do
    inputs = Map.get(entry, "inputs", [])

    cond do
      Map.keys(entry) -- ["identity", "inputs"] != [] ->
        {:error, "native_artifact #{kind}.#{name} has unknown fields"}

      not Regex.match?(@name_pattern, name) ->
        {:error, "native_artifact #{kind} name #{inspect(name)} is invalid"}

      not (is_list(inputs) and
               Enum.all?(inputs, &(is_binary(&1) and relative_inside?(&1)))) ->
        {:error, "native_artifact #{kind}.#{name}.inputs must list relative paths"}

      Enum.uniq(inputs) != inputs ->
        {:error, "native_artifact #{kind}.#{name}.inputs must not repeat paths"}

      true ->
        {:ok, %NativeArtifactInput{name: name, identity: identity, inputs: inputs}}
    end
  end

  defp parse_native_input(kind, name, _),
    do: {:error, "native_artifact #{kind}.#{name} must declare an identity"}

  defp parse_native_targets(targets, toolchains, systems) when is_map(targets) do
    Enum.reduce_while(Enum.sort(targets), {:ok, %{}}, fn {name, entry}, {:ok, acc} ->
      case parse_native_target(name, entry, toolchains, systems) do
        {:ok, target} -> {:cont, {:ok, Map.put(acc, name, target)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp parse_native_targets(_, _, _),
    do: {:error, "native_artifact targets must be a mapping"}

  defp parse_native_target(name, entry, toolchains, systems)
       when is_binary(name) and is_map(entry) do
    fields = ~w(operating_system architecture endianness libc abi toolchain system)
    values = Map.take(entry, fields)

    cond do
      not Regex.match?(@name_pattern, name) ->
        {:error, "native_artifact target name #{inspect(name)} is invalid"}

      Map.keys(entry) -- fields != [] ->
        {:error, "native_artifact target #{name} has unknown fields"}

      Enum.any?(fields, &(not (is_binary(values[&1]) and values[&1] != ""))) ->
        {:error, "native_artifact target #{name} must declare #{Enum.join(fields, ", ")}"}

      not Map.has_key?(toolchains, values["toolchain"]) ->
        {:error,
         "native_artifact target #{name} uses unknown toolchain #{inspect(values["toolchain"])}"}

      not Map.has_key?(systems, values["system"]) ->
        {:error, "native_artifact target #{name} uses unknown system #{inspect(values["system"])}"}

      true ->
        {:ok,
         struct!(NativeArtifactTarget,
           name: name,
           operating_system: values["operating_system"],
           architecture: values["architecture"],
           endianness: values["endianness"],
           libc: values["libc"],
           abi: values["abi"],
           toolchain: values["toolchain"],
           system: values["system"]
         )}
    end
  end

  defp parse_native_target(name, _, _, _),
    do: {:error, "native_artifact target #{name} must be a mapping"}

  defp parse_native_smoke(smoke, packages, targets) when is_list(smoke) do
    parsed = Enum.map(smoke, &parse_native_smoke_cell(&1, packages, targets))

    case Enum.find(parsed, &match?({:error, _}, &1)) do
      nil ->
        cells = Enum.map(parsed, &elem(&1, 1))

        if Enum.uniq(cells) == cells,
          do: {:ok, cells},
          else: {:error, "native_artifact smoke must not repeat a cell"}

      {:error, message} ->
        {:error, message}
    end
  end

  defp parse_native_smoke(_, _, _), do: {:error, "native_artifact smoke must be a list"}

  defp parse_native_smoke_cell(
         %{"package" => package, "profile" => profile, "target" => target} = entry,
         packages,
         targets
       ) do
    cond do
      Map.keys(entry) -- ["package", "profile", "target"] != [] ->
        {:error, "native_artifact smoke cell has unknown fields"}

      not Map.has_key?(packages, package) ->
        {:error, "native_artifact smoke uses unknown package #{inspect(package)}"}

      not Enum.any?(packages[package].native_artifacts, &(&1.profile == profile)) ->
        {:error, "native_artifact smoke uses undeclared profile #{package}/#{profile}"}

      not Map.has_key?(targets, target) ->
        {:error, "native_artifact smoke uses unknown target #{inspect(target)}"}

      true ->
        {:ok, %{package: package, profile: profile, target: target}}
    end
  end

  defp parse_native_smoke_cell(_, _, _),
    do: {:error, "native_artifact smoke cells need package, profile and target"}

  defp parse_hosts(name, hosts) when is_list(hosts) do
    parsed = Enum.map(hosts, &parse_host/1)

    cond do
      :error in parsed ->
        {:error,
         "package #{name}: every host needs a relative path inside the package " <>
           "and may set env (NAME: value strings)"}

      Enum.uniq_by(parsed, &elem(&1, 1).path) != parsed ->
        {:error, "package #{name}: hosts must not repeat a path"}

      true ->
        {:ok, Enum.map(parsed, &elem(&1, 1))}
    end
  end

  defp parse_hosts(name, _), do: {:error, "package #{name}: hosts must be a list"}

  defp parse_host(%{"path" => path} = entry) when is_binary(path) do
    env = Map.get(entry, "env", %{})

    with [] <- Map.keys(entry) -- ["path", "env"],
         true <- relative_inside?(path),
         true <- is_map(env),
         true <- Enum.all?(env, &env_pair?/1) do
      {:ok, %Host{path: path, env: Enum.sort(env)}}
    else
      _ -> :error
    end
  end

  defp parse_host(_), do: :error

  defp relative_inside?(path) do
    segments = Path.split(path)

    path != "" and Path.type(path) == :relative and ".." not in segments and "." not in segments
  end

  defp env_pair?({key, value}),
    do: is_binary(key) and Regex.match?(~r/^[A-Z][A-Z0-9_]*$/, key) and is_binary(value)

  defp parse_lanes(lanes) when is_map(lanes) do
    Enum.reduce_while(lanes, {:ok, %{}}, fn
      {name, %{"elixir" => elixir, "otp" => otp} = lane}, {:ok, acc}
      when is_binary(name) and is_binary(elixir) and is_binary(otp) ->
        case parse_skip(Map.get(lane, "skip", [])) do
          {:ok, skip} ->
            {:cont, {:ok, Map.put(acc, name, %{elixir: elixir, otp: otp, skip: skip})}}

          :error ->
            {:halt, {:error, "lane #{inspect(name)}: skip must list tool names"}}
        end

      {name, _}, _ ->
        {:halt, {:error, "lane #{inspect(name)} must declare elixir and otp"}}
    end)
  end

  defp parse_lanes(_), do: {:error, "lanes must be a mapping"}

  defp parse_skip(skip) when is_list(skip) do
    if Enum.all?(skip, &is_binary/1), do: {:ok, skip}, else: :error
  end

  defp parse_skip(_), do: :error

  defp parse_globs(globs) when is_list(globs) do
    if Enum.all?(globs, &is_binary/1),
      do: {:ok, globs},
      else: {:error, "select_all_on must list glob patterns"}
  end

  defp parse_globs(_), do: {:error, "select_all_on must be a list"}

  defp check_dependencies(packages) do
    missing =
      for {name, package} <- Enum.sort(packages),
          dependency <- package.depends_on,
          not Map.has_key?(packages, dependency),
          do: "package #{name} depends on unknown package #{inspect(dependency)}"

    case missing do
      [] -> :ok
      [first | _] -> {:error, first}
    end
  end

  # Kahn's algorithm with alphabetical tie-breaking. Anything left over
  # belongs to a cycle.
  defp topological_sort(packages) do
    in_degree = Map.new(packages, fn {name, package} -> {name, length(package.depends_on)} end)
    dependents = build_dependents(packages)

    ready = for {name, 0} <- in_degree, do: name

    {order, remaining} = kahn(Enum.sort(ready), in_degree, dependents, [])

    case Enum.filter(remaining, fn {_, degree} -> degree > 0 end) do
      [] ->
        {:ok, Enum.reverse(order)}

      cyclic ->
        names = Enum.sort(Enum.map(cyclic, &elem(&1, 0)))
        {:error, "dependency cycle among #{Enum.join(names, ", ")}"}
    end
  end

  defp build_dependents(packages) do
    Enum.reduce(packages, %{}, fn {name, package}, acc ->
      Enum.reduce(package.depends_on, acc, fn dependency, acc ->
        Map.update(acc, dependency, [name], &[name | &1])
      end)
    end)
  end

  defp kahn([], in_degree, _, order), do: {order, in_degree}

  defp kahn([name | ready], in_degree, dependents, order) do
    {in_degree, released} =
      dependents
      |> Map.get(name, [])
      |> Enum.reduce({Map.delete(in_degree, name), []}, fn dependent, {degrees, released} ->
        degree = Map.fetch!(degrees, dependent) - 1
        degrees = Map.put(degrees, dependent, degree)
        if degree == 0, do: {degrees, [dependent | released]}, else: {degrees, released}
      end)

    kahn(Enum.sort(ready ++ released), in_degree, dependents, [name | order])
  end

  defp close_over(set, next) do
    additions =
      set
      |> Enum.flat_map(next)
      |> MapSet.new()
      |> MapSet.difference(set)

    if MapSet.size(additions) == 0, do: set, else: close_over(MapSet.union(set, additions), next)
  end

  defp prefix(nil, message), do: message
  defp prefix(path, message), do: "#{path}: #{message}"
end
