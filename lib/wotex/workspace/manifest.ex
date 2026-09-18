defmodule Wotex.Workspace.Manifest do
  @moduledoc """
  The package manifest, `tooling/packages.yaml`.

  The manifest is the single source for the package dependency graph. Loading
  validates it: every `depends_on` entry names a manifest package and the
  graph has no cycle. Functions that take a manifest default to the
  repository's own; tests pass fixture manifests built with `from_map/2`.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.NativeSuite

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
      hosts: []
    ]
  end

  @type lane :: %{elixir: String.t(), otp: String.t(), skip: [String.t()]}

  @type t :: %__MODULE__{
          path: Path.t() | nil,
          schema_version: String.t() | nil,
          lanes: %{String.t() => lane()},
          select_all_on: [String.t()],
          packages: %{String.t() => Package.t()},
          order: [String.t()]
        }

  defstruct path: nil, schema_version: nil, lanes: %{}, select_all_on: [], packages: %{}, order: []

  @name_pattern ~r/^[a-z][a-z0-9-]*$/

  @doc "Path of the repository's manifest."
  @spec default_path() :: Path.t()
  def default_path, do: Path.join(Workspace.root(), "tooling/packages.yaml")

  @doc "Loads and validates a manifest file."
  @spec load(Path.t()) :: {:ok, t()} | {:error, String.t()}
  def load(path \\ default_path()) do
    case YamlElixir.read_from_file(path) do
      {:ok, map} when is_map(map) -> from_map(map, path)
      {:ok, _other} -> {:error, "#{path}: the manifest must be a mapping"}
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
         {:ok, globs} <- parse_globs(Map.get(map, "select_all_on", [])) do
      {:ok,
       %__MODULE__{
         path: path,
         schema_version: Map.get(map, "schema_version"),
         lanes: lanes,
         select_all_on: globs,
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
    _package = fetch!(name, manifest)
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
    _package = fetch!(name, manifest)

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
    _package = fetch!(name, manifest)
    closure = close_over(MapSet.new([name]), &dependents(&1, manifest))
    Enum.filter(manifest.order, &(&1 != name and MapSet.member?(closure, &1)))
  end

  @doc """
  Every package that `name` depends on directly or through other packages,
  in topological order. `name` itself is not included.
  """
  @spec transitive_dependencies(String.t(), t()) :: [String.t()]
  def transitive_dependencies(name, %__MODULE__{} = manifest \\ load!()) do
    _package = fetch!(name, manifest)
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

  defp parse_packages(_other), do: {:error, "packages must be a non-empty mapping"}

  defp parse_package(name, entry) when is_binary(name) and is_map(entry) do
    with :ok <- check_name(name),
         {:ok, app} <- parse_app(name, Map.get(entry, "app")),
         {:ok, depends_on} <- parse_depends_on(name, Map.get(entry, "depends_on", [])),
         {:ok, native} <- parse_boolean(name, "native", Map.get(entry, "native", false)),
         {:ok, native_task} <- parse_task(name, "native_task", Map.get(entry, "native_task")),
         {:ok, software_task} <-
           parse_task(name, "software_task", Map.get(entry, "software_task")),
         {:ok, native_check} <- NativeSuite.parse_all(name, Map.get(entry, "native_check")),
         {:ok, hosts} <- parse_hosts(name, Map.get(entry, "hosts", [])) do
      {:ok,
       %Package{
         name: name,
         app: app,
         depends_on: depends_on,
         native: native,
         native_task: native_task,
         software_task: software_task,
         native_check: native_check,
         hosts: hosts
       }}
    end
  end

  defp parse_package(name, _entry), do: {:error, "package #{inspect(name)} must be a mapping"}

  defp check_name(name) do
    if Regex.match?(@name_pattern, name),
      do: :ok,
      else: {:error, "package name #{inspect(name)} is not lowercase-with-dashes"}
  end

  defp parse_app(_name, app) when is_binary(app) and app != "" do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, app),
      do: {:ok, app},
      else: {:error, "app #{inspect(app)} is not a valid OTP application name"}
  end

  defp parse_app(name, _app), do: {:error, "package #{name}: app is required"}

  defp parse_depends_on(name, list) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      {:ok, Enum.uniq(list)}
    else
      {:error, "package #{name}: depends_on must list package names"}
    end
  end

  defp parse_depends_on(name, _other), do: {:error, "package #{name}: depends_on must be a list"}

  defp parse_boolean(_name, _key, value) when is_boolean(value), do: {:ok, value}
  defp parse_boolean(name, key, _value), do: {:error, "package #{name}: #{key} must be a boolean"}

  defp parse_task(_name, _key, nil), do: {:ok, nil}
  defp parse_task(_name, _key, task) when is_binary(task) and task != "", do: {:ok, task}
  defp parse_task(name, key, _task), do: {:error, "package #{name}: #{key} must be a task name"}

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

  defp parse_hosts(name, _other), do: {:error, "package #{name}: hosts must be a list"}

  defp parse_host(%{"path" => path} = entry) when is_binary(path) do
    env = Map.get(entry, "env", %{})

    with [] <- Map.keys(entry) -- ["path", "env"],
         true <- relative_inside?(path),
         true <- is_map(env),
         true <- Enum.all?(env, &env_pair?/1) do
      {:ok, %Host{path: path, env: Enum.sort(env)}}
    else
      _invalid -> :error
    end
  end

  defp parse_host(_entry), do: :error

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

      {name, _other}, _acc ->
        {:halt, {:error, "lane #{inspect(name)} must declare elixir and otp"}}
    end)
  end

  defp parse_lanes(_other), do: {:error, "lanes must be a mapping"}

  defp parse_skip(skip) when is_list(skip) do
    if Enum.all?(skip, &is_binary/1), do: {:ok, skip}, else: :error
  end

  defp parse_skip(_other), do: :error

  defp parse_globs(globs) when is_list(globs) do
    if Enum.all?(globs, &is_binary/1),
      do: {:ok, globs},
      else: {:error, "select_all_on must list glob patterns"}
  end

  defp parse_globs(_other), do: {:error, "select_all_on must be a list"}

  defp check_dependencies(packages) do
    missing =
      for {name, package} <- Enum.sort(packages),
          dependency <- package.depends_on,
          not Map.has_key?(packages, dependency),
          do: "package #{name} depends on unknown package #{inspect(dependency)}"

    case missing do
      [] -> :ok
      [first | _rest] -> {:error, first}
    end
  end

  # Kahn's algorithm with alphabetical tie-breaking. Anything left over
  # belongs to a cycle.
  defp topological_sort(packages) do
    in_degree = Map.new(packages, fn {name, package} -> {name, length(package.depends_on)} end)
    dependents = build_dependents(packages)

    ready = for {name, 0} <- in_degree, do: name

    {order, remaining} = kahn(Enum.sort(ready), in_degree, dependents, [])

    case Enum.filter(remaining, fn {_name, degree} -> degree > 0 end) do
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

  defp kahn([], in_degree, _dependents, order), do: {order, in_degree}

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
