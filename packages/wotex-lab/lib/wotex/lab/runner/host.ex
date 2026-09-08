defmodule Wotex.Lab.Runner.Host do
  @moduledoc """
  Explicit host configuration for a run: trusted component modules keyed by
  capability, the owning `Wotex.Lab` instance, a caller clock, an optional
  seed override, budgets and an optional observer pid.

  `new/1` validates that every module implements both `Wotex.Lab.Plugin` and
  `Wotex.Lab.Component`, that capability ids are unique across modules, that
  the instance is a live pid and that the budgets are admissible. It opens no
  connection and starts no child; `available?/2` only inspects capabilities.
  """

  alias Wotex.Lab.{Component, Error, Options, Plugin}
  alias Wotex.Lab.Runner.Budgets

  @type t :: %__MODULE__{
          modules: %{String.t() => module()},
          configs: %{module() => keyword()},
          instance: pid(),
          clock: (-> integer()),
          seed: non_neg_integer() | nil,
          budgets: Budgets.t(),
          observer: pid() | nil,
          work_root: Path.t(),
          dependency_versions: %{String.t() => String.t()}
        }

  @enforce_keys [
    :modules,
    :configs,
    :instance,
    :clock,
    :budgets,
    :work_root,
    :dependency_versions
  ]
  defstruct modules: %{},
            configs: %{},
            instance: nil,
            clock: nil,
            seed: nil,
            budgets: nil,
            observer: nil,
            work_root: nil,
            dependency_versions: %{}

  @doc "Builds a host from `:modules` (list of `{module, config}` or modules), `:instance`, `:clock`, `:seed`, `:budgets`, `:observer`, `:work_root`."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    dependency_versions = Keyword.get(opts, :dependency_versions, %{})

    with :ok <-
           Options.validate(opts, [
             :modules,
             :instance,
             :clock,
             :seed,
             :budgets,
             :observer,
             :work_root,
             :dependency_versions
           ]),
         :ok <- dependencies(dependency_versions),
         {:ok, modules, configs} <-
           modules(Keyword.get(opts, :modules, []), dependency_versions),
         :ok <- instance(Keyword.get(opts, :instance)),
         {:ok, budgets} <- Budgets.new(Keyword.get(opts, :budgets, %{})),
         :ok <- observer(Keyword.get(opts, :observer)),
         :ok <- seed(Keyword.get(opts, :seed)),
         :ok <- clock(Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)),
         :ok <- work_root(Keyword.get(opts, :work_root, default_work_root())) do
      {:ok,
       %__MODULE__{
         modules: modules,
         configs: configs,
         instance: Keyword.fetch!(opts, :instance),
         clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
         seed: Keyword.get(opts, :seed),
         budgets: budgets,
         observer: Keyword.get(opts, :observer),
         work_root: Keyword.get(opts, :work_root, default_work_root()),
         dependency_versions: dependency_versions
       }}
    end
  end

  def new(_opts),
    do: {:error, Error.new(:invalid_host, :preflight, "host options must be a keyword list")}

  @doc "Capabilities the host can serve."
  @spec capabilities(t()) :: [String.t()]
  def capabilities(%__MODULE__{modules: modules}), do: modules |> Map.keys() |> Enum.sort()

  @doc false
  @spec revalidate(term()) :: {:ok, t()} | {:error, Error.t()}
  def revalidate(%__MODULE__{} = host) do
    entries = Enum.map(host.configs, fn {module, config} -> {module, config} end)

    case new(
           modules: entries,
           instance: host.instance,
           clock: host.clock,
           seed: host.seed,
           budgets: host.budgets,
           observer: host.observer,
           work_root: host.work_root,
           dependency_versions: host.dependency_versions
         ) do
      {:ok, rebuilt} ->
        if rebuilt.modules == host.modules,
          do: {:ok, rebuilt},
          else: {:error, Error.new(:invalid_host, :preflight, "host capability map is forged")}

      {:error, error} ->
        {:error, error}
    end
  rescue
    _exception -> {:error, Error.new(:invalid_host, :preflight, "host struct is forged")}
  end

  def revalidate(_host),
    do: {:error, Error.new(:invalid_host, :preflight, "host is invalid")}

  defp modules(entries, dependency_versions) when is_list(entries) and length(entries) <= 256 do
    initial = {%{}, %{}, MapSet.new()}

    Enum.reduce_while(entries, {:ok, initial}, fn entry, {:ok, acc} ->
      case add_module(entry, acc, dependency_versions) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, {modules, configs, _ids}} -> {:ok, modules, configs}
      {:error, error} -> {:error, error}
    end
  end

  defp modules(_entries, _dependency_versions),
    do: {:error, Error.new(:invalid_host, :preflight, "modules must be a list")}

  defp add_module(entry, {modules, configs, ids}, dependency_versions) do
    with {:ok, module, config} <- module_entry(entry),
         {:ok, id, capabilities} <- metadata(module, dependency_versions),
         :ok <- unique_id(id, ids),
         :ok <- unique_capabilities(capabilities, modules) do
      modules = Enum.reduce(capabilities, modules, &Map.put(&2, &1, module))
      {:ok, {modules, Map.put(configs, module, config), MapSet.put(ids, id)}}
    end
  end

  defp module_entry({module, config}), do: validate_module_entry(module, config)
  defp module_entry(module), do: validate_module_entry(module, [])

  defp validate_module_entry(module, config) do
    with :ok <- loaded_component(module),
         :ok <- component_config(config, module) do
      {:ok, module, config}
    end
  end

  defp loaded_component(module) when is_atom(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        invalid_module(module, "component module is not loaded")

      Enum.all?([{:execute, 3}, {:capabilities, 0}, {:child_specs, 1}, {:manifest, 0}], fn
        {function, arity} -> function_exported?(module, function, arity)
      end) ->
        :ok

      true ->
        {:error,
         Error.new(
           :invalid_host,
           :preflight,
           "component must implement Wotex.Lab.Plugin and Wotex.Lab.Component",
           details: %{module: module, plugin: Plugin, component: Component}
         )}
    end
  end

  defp loaded_component(module), do: invalid_module(module, "component module is not loaded")

  defp invalid_module(module, message),
    do: {:error, Error.new(:invalid_host, :preflight, message, details: %{module: module})}

  defp component_config(config, module) do
    keys = if Keyword.keyword?(config), do: Keyword.keys(config), else: []
    reserved? = Enum.any?([:attempt_id, :seed, :instance], &(&1 in keys))

    if Keyword.keyword?(config) and keys == Enum.uniq(keys) and not reserved?,
      do: :ok,
      else:
        {:error,
         Error.new(:invalid_host, :preflight, "component config must be unique keywords",
           details: %{module: module}
         )}
  end

  defp metadata(module, dependency_versions) do
    id = module.id()
    capabilities = module.capabilities()
    manifest = module.manifest()

    validate_metadata(id, capabilities, manifest, dependency_versions)
  rescue
    _exception ->
      {:error, Error.new(:invalid_plugin, :preflight, "plugin inspection raised")}
  catch
    _kind, _reason ->
      {:error, Error.new(:invalid_plugin, :preflight, "plugin inspection failed")}
  end

  defp validate_metadata(id, capabilities, manifest, dependency_versions) do
    with :ok <- plugin_id(id),
         :ok <- plugin_capabilities(capabilities),
         :ok <- plugin_manifest(manifest, id, capabilities),
         :ok <- plugin_dependencies(manifest, dependency_versions) do
      {:ok, id, capabilities}
    end
  end

  defp plugin_id(id) do
    if Options.identifier?(id),
      do: :ok,
      else: {:error, Error.new(:invalid_plugin, :preflight, "plugin id is invalid")}
  end

  defp plugin_capabilities(capabilities) when is_list(capabilities) do
    valid =
      length(capabilities) in 1..64 and Enum.all?(capabilities, &Options.identifier?/1) and
        Enum.uniq(capabilities) == capabilities

    if valid,
      do: :ok,
      else: invalid_capabilities()
  end

  defp plugin_capabilities(_capabilities), do: invalid_capabilities()

  defp invalid_capabilities,
    do:
      {:error,
       Error.new(:invalid_plugin, :preflight, "plugin capabilities must be unique identifiers")}

  defp plugin_manifest(manifest, id, capabilities) do
    if valid_manifest?(manifest, id, capabilities),
      do: :ok,
      else:
        {:error, Error.new(:invalid_plugin_manifest, :preflight, "plugin manifest is incomplete")}
  end

  defp plugin_dependencies(manifest, dependency_versions) do
    case missing_dependencies(manifest["dependencies"], dependency_versions) do
      [] ->
        :ok

      missing ->
        {:error,
         Error.new(
           :dependency_mismatch,
           :preflight,
           "host does not satisfy plugin dependency versions",
           details: %{dependencies: missing}
         )}
    end
  end

  defp valid_manifest?(manifest, id, capabilities) when is_map(manifest) do
    [
      manifest["id"] == id,
      manifest["capabilities"] == capabilities,
      bounded_string?(manifest["version"]),
      bounded_string?(manifest["package"]),
      manifest["instance_scope"] == "per_instance",
      string_list?(manifest["behaviours"]),
      is_map(manifest["configuration"]),
      is_map(manifest["ownership"]),
      is_map(manifest["limits"]),
      string_list?(manifest["fixtures"]),
      string_list?(manifest["evidence"]),
      is_map(manifest["cleanup"]),
      is_map(manifest["dependencies"])
    ]
    |> Enum.all?()
  end

  defp valid_manifest?(_manifest, _id, _capabilities), do: false

  defp missing_dependencies(required, available) do
    Enum.flat_map(required, fn {package, version} ->
      if Map.get(available, package) == version, do: [], else: [package]
    end)
  end

  defp unique_id(id, ids) do
    if MapSet.member?(ids, id),
      do: {:error, Error.new(:duplicate_plugin, :preflight, "plugin ids must be unique")},
      else: :ok
  end

  defp unique_capabilities(capabilities, modules) do
    case Enum.find(capabilities, &Map.has_key?(modules, &1)) do
      nil ->
        :ok

      duplicate ->
        {:error,
         Error.new(:duplicate_capability, :preflight, "two components claim one capability",
           details: %{capability: duplicate}
         )}
    end
  end

  defp dependencies(versions) when is_map(versions) and map_size(versions) <= 256 do
    if Enum.all?(versions, fn {package, version} ->
         bounded_string?(package) and bounded_string?(version)
       end),
       do: :ok,
       else: {:error, Error.new(:invalid_host, :preflight, "dependency versions are invalid")}
  end

  defp dependencies(_versions),
    do: {:error, Error.new(:invalid_host, :preflight, "dependency versions must be a map")}

  defp instance(pid) when is_pid(pid) do
    if Process.alive?(pid),
      do: :ok,
      else: {:error, Error.new(:invalid_host, :preflight, "instance is not alive")}
  end

  defp instance(_other),
    do: {:error, Error.new(:invalid_host, :preflight, "instance must be a live Wotex.Lab pid")}

  defp observer(nil), do: :ok

  defp observer(pid) when is_pid(pid) do
    if Process.alive?(pid),
      do: :ok,
      else: {:error, Error.new(:invalid_host, :preflight, "observer is not alive")}
  end

  defp observer(_other),
    do: {:error, Error.new(:invalid_host, :preflight, "observer must be a pid")}

  defp seed(nil), do: :ok
  defp seed(seed) when is_integer(seed) and seed >= 0 and seed <= 4_294_967_295, do: :ok

  defp seed(_seed),
    do: {:error, Error.new(:invalid_host, :preflight, "seed must be an integer in 0..4294967295")}

  defp clock(clock) when is_function(clock, 0), do: :ok
  defp clock(_clock), do: {:error, Error.new(:invalid_host, :preflight, "clock must be a function")}

  defp work_root(path) when is_binary(path) and byte_size(path) in 1..4_096 do
    if Path.type(path) == :absolute,
      do: :ok,
      else: {:error, Error.new(:invalid_host, :preflight, "work root must be an absolute path")}
  end

  defp work_root(_path),
    do: {:error, Error.new(:invalid_host, :preflight, "work root must be a bounded path")}

  defp bounded_string?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)

  defp string_list?(values) when is_list(values) and length(values) <= 256,
    do: Enum.all?(values, &bounded_string?/1)

  defp string_list?(_values), do: false

  defp default_work_root, do: Path.join(System.tmp_dir!(), "wotex-lab-runs")
end
