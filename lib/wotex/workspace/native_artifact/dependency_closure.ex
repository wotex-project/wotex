defmodule Wotex.Workspace.NativeArtifact.DependencyClosure do
  @moduledoc """
  Target-aware dependency closure for assembled ELF artifacts.

  Resolution is restricted to the exact root filesystem and artifact roots
  supplied by the caller. Host paths, host linker caches and filename-only
  fallbacks are never consulted.
  """

  alias Wotex.Workspace.Manifest.NativeArtifactInput
  alias Wotex.Workspace.Manifest.NativeArtifactTarget
  alias Wotex.Workspace.NativeArtifact.ELF

  defmodule Limits do
    @moduledoc "Bounds for root and artifact tree inspection."

    @type t :: %__MODULE__{
            entries: pos_integer(),
            depth: pos_integer(),
            path_bytes: pos_integer(),
            elf_files: pos_integer(),
            symlink_depth: pos_integer(),
            elf_bytes: pos_integer()
          }

    defstruct entries: 200_000,
              depth: 128,
              path_bytes: 4_096,
              elf_files: 50_000,
              symlink_depth: 32,
              elf_bytes: 536_870_912
  end

  defmodule Artifact do
    @moduledoc "One verified artifact payload admitted to an assembly."

    @type t :: %__MODULE__{
            name: String.t(),
            path: Path.t(),
            target: String.t(),
            build_identity: String.t(),
            payload_identity: String.t(),
            external_libraries: [String.t()]
          }

    @enforce_keys [:name, :path, :target, :build_identity, :payload_identity]
    defstruct name: nil,
              path: nil,
              target: nil,
              build_identity: nil,
              payload_identity: nil,
              external_libraries: []
  end

  defmodule Result do
    @moduledoc "A complete, compatible dependency closure."

    @enforce_keys [
      :target,
      :architecture,
      :endianness,
      :system,
      :system_identity,
      :artifacts,
      :files,
      :edges
    ]
    defstruct @enforce_keys
  end

  @doc "Checks all reachable ELF dependencies in one exact target assembly."
  @spec check(
          [Artifact.t()],
          Path.t(),
          NativeArtifactTarget.t(),
          NativeArtifactInput.t(),
          Limits.t()
        ) :: {:ok, Result.t()} | {:error, [String.t()]}
  def check(
        artifacts,
        rootfs,
        %NativeArtifactTarget{} = target,
        %NativeArtifactInput{} = system,
        %Limits{} = limits \\ %Limits{}
      ) do
    with :ok <- validate_limits(limits),
         :ok <- validate_assembly(artifacts, rootfs, target, system),
         {:ok, rootfs_scan} <- scan_source(root_source(rootfs), limits),
         {:ok, artifact_scans} <- scan_artifacts(artifacts, limits),
         {:ok, context} <- context(rootfs_scan, artifact_scans, limits),
         {:ok, files, edges} <- closure(context, target) do
      {:ok,
       %Result{
         target: target.name,
         architecture: target.architecture,
         endianness: target.endianness,
         system: system.name,
         system_identity: system.identity,
         artifacts: artifact_records(artifacts),
         files: files,
         edges: edges
       }}
    end
  end

  defp validate_limits(limits) do
    invalid =
      limits
      |> Map.from_struct()
      |> Enum.reject(fn {_, value} -> is_integer(value) and value > 0 end)

    if invalid == [],
      do: :ok,
      else: {:error, ["dependency-closure limits must be positive integers"]}
  end

  defp validate_assembly([], _, _, _), do: {:error, ["assembly requires at least one artifact"]}

  defp validate_assembly(artifacts, rootfs, target, system) do
    errors =
      []
      |> root_errors(rootfs)
      |> system_errors(target, system)
      |> artifact_errors(artifacts, target)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp root_errors(errors, rootfs) do
    case ordinary_root(rootfs, "root filesystem") do
      :ok -> errors
      {:error, message} -> [message | errors]
    end
  end

  defp system_errors(errors, target, system) do
    if target.system == system.name,
      do: errors,
      else: [
        "target system #{target.system} does not match supplied system #{system.name}" | errors
      ]
  end

  defp artifact_errors(errors, artifacts, target) do
    names = Enum.map(artifacts, & &1.name)

    errors =
      if names == Enum.uniq(names),
        do: errors,
        else: ["assembly repeats an artifact name" | errors]

    Enum.reduce(artifacts, errors, fn artifact, acc ->
      acc
      |> artifact_root_error(artifact)
      |> artifact_target_error(artifact, target)
      |> artifact_identity_errors(artifact)
    end)
  end

  defp artifact_root_error(errors, artifact) do
    case ordinary_root(artifact.path, "artifact #{artifact.name}") do
      :ok -> errors
      {:error, message} -> [message | errors]
    end
  end

  defp artifact_target_error(errors, %{target: target}, %{name: target}), do: errors

  defp artifact_target_error(errors, artifact, target) do
    ["artifact #{artifact.name} targets #{artifact.target}, expected #{target.name}" | errors]
  end

  defp artifact_identity_errors(errors, artifact) do
    Enum.reduce(
      [
        {artifact.build_identity, "build identity"},
        {artifact.payload_identity, "payload identity"}
      ],
      errors,
      fn {identity, label}, acc ->
        if full_digest?(identity),
          do: acc,
          else: ["artifact #{artifact.name} has an invalid #{label}" | acc]
      end
    )
  end

  defp ordinary_root(path, label) do
    if is_binary(path) and Path.type(path) == :absolute do
      case File.lstat(path) do
        {:ok, %{type: :directory}} -> :ok
        {:ok, %{type: type}} -> {:error, "#{label} is #{type}, expected directory"}
        {:error, reason} -> {:error, "#{label}: #{:file.format_error(reason)}"}
      end
    else
      {:error, "#{label} path must be absolute"}
    end
  end

  defp root_source(root), do: %{name: "rootfs", root: root, kind: :rootfs, artifact: nil}

  defp artifact_source(artifact) do
    %{name: artifact.name, root: artifact.path, kind: :artifact, artifact: artifact}
  end

  defp scan_artifacts(artifacts, limits) do
    artifacts
    |> Enum.reduce_while({:ok, []}, fn artifact, {:ok, scans} ->
      case scan_source(artifact_source(artifact), limits) do
        {:ok, scan} -> {:cont, {:ok, [scan | scans]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> reverse_scans()
  end

  defp reverse_scans({:ok, scans}), do: {:ok, Enum.reverse(scans)}
  defp reverse_scans({:error, _} = error), do: error

  defp scan_source(source, limits) do
    state = %{
      source: source,
      entries: 0,
      elf_files: 0,
      providers: %{},
      paths: %{"" => :directory},
      symlinks: %{}
    }

    case walk_directory(source.root, "", 0, state, limits) do
      {:ok, scanned} -> add_symlink_aliases(scanned, limits)
      {:error, message} -> {:error, ["#{source.name}: #{message}"]}
    end
  end

  defp walk_directory(_, _, depth, _, limits) when depth > limits.depth,
    do: {:error, "tree exceeds nesting depth #{limits.depth}"}

  defp walk_directory(root, relative, depth, state, limits) do
    case File.ls(absolute(root, relative)) do
      {:ok, names} -> walk_names(Enum.sort(names), root, relative, depth, state, limits)
      {:error, reason} -> {:error, "#{display_path(relative)}: #{:file.format_error(reason)}"}
    end
  end

  defp walk_names([], _, _, _, state, _), do: {:ok, state}

  defp walk_names([name | names], root, parent, depth, state, limits) do
    relative = join_relative(parent, name)

    with :ok <- validate_tree_path(relative, limits),
         {:ok, next} <- count_entry(state, limits),
         {:ok, next} <- walk_entry(root, relative, depth, next, limits) do
      walk_names(names, root, parent, depth, next, limits)
    end
  end

  defp walk_entry(root, relative, depth, state, limits) do
    case File.lstat(absolute(root, relative)) do
      {:ok, %{type: :directory}} ->
        state = put_in(state.paths[relative], :directory)
        walk_directory(root, relative, depth + 1, state, limits)

      {:ok, %{type: :regular}} ->
        inspect_regular(root, relative, state, limits)

      {:ok, %{type: :symlink}} ->
        inspect_symlink(root, relative, state)

      {:ok, %{type: type}} ->
        special_entry(relative, type, state)

      {:error, reason} ->
        {:error, "#{relative}: #{:file.format_error(reason)}"}
    end
  end

  defp inspect_regular(root, relative, state, limits) do
    state = put_in(state.paths[relative], :regular)
    path = absolute(root, relative)

    if ELF.file?(path) do
      with {:ok, next} <- count_elf(state, limits),
           {:ok, elf} <- ELF.inspect(path, max_bytes: limits.elf_bytes) do
        provider = provider(state.source, relative, elf)
        {:ok, put_in(next.providers[relative], provider)}
      end
    else
      {:ok, state}
    end
  end

  defp inspect_symlink(root, relative, state) do
    case File.read_link(absolute(root, relative)) do
      {:ok, target} ->
        state =
          state
          |> put_in([:paths, relative], :symlink)
          |> put_in([:symlinks, relative], target)

        {:ok, state}

      {:error, reason} ->
        {:error, "#{relative}: #{:file.format_error(reason)}"}
    end
  end

  defp special_entry(_, _, %{source: %{kind: :rootfs}} = state), do: {:ok, state}

  defp special_entry(relative, type, _),
    do: {:error, "#{relative}: artifact entry kind #{type} is not supported"}

  defp count_entry(state, limits) when state.entries >= limits.entries,
    do: {:error, "tree exceeds #{limits.entries} entries"}

  defp count_entry(state, _), do: {:ok, %{state | entries: state.entries + 1}}

  defp count_elf(state, limits) when state.elf_files >= limits.elf_files,
    do: {:error, "tree exceeds #{limits.elf_files} ELF files"}

  defp count_elf(state, _), do: {:ok, %{state | elf_files: state.elf_files + 1}}

  defp provider(source, relative, elf) do
    %{
      id: source.name <> ":" <> relative,
      source: source.name,
      kind: source.kind,
      artifact: source.artifact,
      real_path: relative,
      paths: [relative],
      elf: elf
    }
  end

  defp add_symlink_aliases(state, limits) do
    result =
      state.symlinks
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce_while({:ok, state.providers}, fn path, {:ok, providers} ->
        case resolve_path(state, path, limits) do
          {:ok, resolved} when is_map_key(providers, resolved) ->
            next = update_in(providers[resolved].paths, &[path | &1])
            {:cont, {:ok, next}}

          {:ok, _} ->
            {:cont, {:ok, providers}}

          {:error, message} ->
            {:halt, {:error, ["#{state.source.name}: #{path}: #{message}"]}}
        end
      end)

    case result do
      {:ok, providers} -> {:ok, %{state | providers: normalize_provider_paths(providers)}}
      {:error, _} = error -> error
    end
  end

  defp normalize_provider_paths(providers) do
    Map.new(providers, fn {path, provider} ->
      paths =
        provider.paths
        |> Enum.uniq()
        |> Enum.sort()

      {path, %{provider | paths: paths}}
    end)
  end

  defp resolve_path(state, path, limits), do: resolve_path(state, path, MapSet.new(), 0, limits)

  defp resolve_path(_, _, _, depth, limits) when depth > limits.symlink_depth,
    do: {:error, "symlink chain exceeds #{limits.symlink_depth} entries"}

  defp resolve_path(state, path, seen, depth, limits) do
    case first_symlink(path, state.symlinks) do
      nil ->
        if Map.has_key?(state.paths, path), do: {:ok, path}, else: {:ok, nil}

      {link, target, remainder} ->
        if MapSet.member?(seen, link) do
          {:error, "symlink cycle reaches #{link}"}
        else
          with {:ok, resolved_target} <- normalize_link(link, target),
               combined <- append_remainder(resolved_target, remainder) do
            resolve_path(state, combined, MapSet.put(seen, link), depth + 1, limits)
          end
        end
    end
  end

  defp first_symlink(path, symlinks) do
    components = String.split(path, "/", trim: true)

    components
    |> Enum.with_index(1)
    |> Enum.find_value(fn {_, count} ->
      prefix =
        components
        |> Enum.take(count)
        |> Enum.join("/")

      case Map.fetch(symlinks, prefix) do
        {:ok, target} -> {prefix, target, Enum.drop(components, count)}
        :error -> nil
      end
    end)
  end

  defp normalize_link(link, target) do
    base = if Path.type(target) == :absolute, do: [], else: Enum.reverse(split_parent(link))
    components = String.split(target, "/", trim: false)

    components
    |> Enum.reduce_while({:ok, base}, fn
      component, {:ok, stack} when component in ["", "."] ->
        {:cont, {:ok, stack}}

      "..", {:ok, []} ->
        {:halt, {:error, "symlink target escapes the source root"}}

      "..", {:ok, [_ | rest]} ->
        {:cont, {:ok, rest}}

      component, {:ok, stack} ->
        if String.valid?(component) and not String.contains?(component, <<0>>),
          do: {:cont, {:ok, [component | stack]}},
          else: {:halt, {:error, "symlink target is not valid UTF-8"}}
    end)
    |> joined_link()
  end

  defp joined_link({:ok, []}), do: {:error, "symlink target resolves to the source root"}

  defp joined_link({:ok, components}) do
    path =
      components
      |> Enum.reverse()
      |> Enum.join("/")

    {:ok, path}
  end

  defp joined_link({:error, _} = error), do: error

  defp split_parent(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.drop(-1)
  end

  defp append_remainder(path, []), do: path
  defp append_remainder(path, remainder), do: path <> "/" <> Enum.join(remainder, "/")

  defp context(rootfs, artifacts, limits) do
    scans = [rootfs | artifacts]

    providers =
      scans
      |> Enum.flat_map(&Map.values(&1.providers))
      |> Enum.sort_by(& &1.id)

    cond do
      Enum.sum(Enum.map(scans, & &1.entries)) > limits.entries ->
        {:error, ["assembly exceeds #{limits.entries} inspected entries"]}

      Enum.sum(Enum.map(scans, & &1.elf_files)) > limits.elf_files ->
        {:error, ["assembly exceeds #{limits.elf_files} ELF files"]}

      true ->
        {:ok,
         %{
           rootfs: rootfs,
           artifacts: artifacts,
           providers: providers,
           by_name: providers_by_name(providers),
           limits: limits
         }}
    end
  end

  defp providers_by_name(providers) do
    providers
    |> Enum.flat_map(fn provider -> Enum.map(provider_names(provider), &{&1, provider}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {name, entries} -> {name, Enum.uniq_by(entries, & &1.id)} end)
  end

  defp provider_names(provider) do
    path_names = Enum.map(provider.paths, &Path.basename/1)
    Enum.sort(Enum.uniq(path_names ++ List.wrap(provider.elf.soname)))
  end

  defp closure(context, target) do
    initial =
      context.artifacts
      |> Enum.flat_map(&Map.values(&1.providers))
      |> Enum.sort_by(& &1.id)

    if initial == [] do
      {:error, ["assembly artifacts contain no ELF files; no format fallback is permitted"]}
    else
      state = traverse(initial, MapSet.new(), [], [], context, target)

      errors =
        state.errors
        |> Enum.uniq()
        |> Enum.sort()

      if errors == [] do
        files =
          state.files
          |> Enum.uniq_by(& &1["id"])
          |> Enum.sort_by(& &1["id"])

        edges = Enum.sort_by(state.edges, &{&1["from"], &1["kind"], &1["name"]})
        {:ok, files, edges}
      else
        {:error, errors}
      end
    end
  end

  defp traverse([], visited, files, edges, _, _),
    do: %{visited: visited, files: files, edges: edges, errors: []}

  defp traverse([provider | rest], visited, files, edges, context, target) do
    if MapSet.member?(visited, provider.id) do
      traverse(rest, visited, files, edges, context, target)
    else
      errors = compatibility_errors(provider, target)

      {interpreter_queue, interpreter_edges, interpreter_errors} =
        resolve_interpreter(provider, context, target)

      {needed_queue, needed_edges, needed_errors} =
        resolve_needed(provider, context, target)

      next =
        traverse(
          rest ++ interpreter_queue ++ needed_queue,
          MapSet.put(visited, provider.id),
          [file_record(provider) | files],
          edges ++ interpreter_edges ++ needed_edges,
          context,
          target
        )

      %{next | errors: errors ++ interpreter_errors ++ needed_errors ++ next.errors}
    end
  end

  defp compatibility_errors(provider, target) do
    expected_class = expected_class(target.architecture)
    elf = provider.elf

    []
    |> mismatch_error(provider, "architecture", target.architecture, elf.architecture)
    |> mismatch_error(provider, "endianness", target.endianness, elf.endianness)
    |> mismatch_error(provider, "class", expected_class, elf.class)
  end

  defp mismatch_error(errors, _, _, expected, expected), do: errors

  defp mismatch_error(errors, provider, field, expected, actual) do
    ["#{provider.id}: incompatible ELF #{field}; expected #{expected}, got #{actual}" | errors]
  end

  defp resolve_interpreter(%{elf: %{interpreter: nil}}, _, _), do: {[], [], []}

  defp resolve_interpreter(provider, context, target) do
    relative = String.trim_leading(provider.elf.interpreter, "/")

    case resolve_path(context.rootfs, relative, context.limits) do
      {:ok, resolved} when is_map_key(context.rootfs.providers, resolved) ->
        dependency = context.rootfs.providers[resolved]
        errors = compatibility_errors(dependency, target)

        {[dependency], [edge(provider, dependency, "interpreter", provider.elf.interpreter)],
         errors}

      {:ok, resolved} when is_binary(resolved) ->
        {[], [], ["#{provider.id}: interpreter #{provider.elf.interpreter} is not an ELF file"]}

      {:ok, nil} ->
        {[], [], ["#{provider.id}: unresolved interpreter #{provider.elf.interpreter}"]}

      {:error, message} ->
        {[], [], ["#{provider.id}: interpreter #{message}"]}
    end
  end

  defp resolve_needed(provider, context, target) do
    Enum.reduce(provider.elf.needed, {[], [], []}, fn name, {queue, edges, errors} ->
      case select_provider(Map.get(context.by_name, name, [])) do
        {:ok, dependency, equivalents} ->
          next_errors = compatibility_errors(dependency, target)
          next_edge = edge(provider, dependency, "needed", name, equivalents)
          {[dependency | queue], [next_edge | edges], next_errors ++ errors}

        {:error, :missing} ->
          {queue, edges, ["#{provider.id}: unresolved DT_NEEDED #{name}" | errors]}

        {:error, {:conflict, providers}} ->
          labels =
            providers
            |> Enum.map(& &1.id)
            |> Enum.sort()
            |> Enum.join(", ")

          message = "#{provider.id}: conflicting providers for DT_NEEDED #{name}: #{labels}"
          {queue, edges, [message | errors]}
      end
    end)
  end

  defp select_provider([]), do: {:error, :missing}

  defp select_provider(providers) do
    groups = Enum.group_by(providers, &provider_signature/1)

    case Map.values(groups) do
      [equivalents] ->
        ordered = Enum.sort_by(equivalents, & &1.id)
        {:ok, hd(ordered), ordered}

      _ ->
        {:error, {:conflict, providers}}
    end
  end

  defp provider_signature(provider) do
    elf = provider.elf
    {elf.sha256, elf.class, elf.architecture, elf.endianness, elf.soname}
  end

  defp edge(from, provider, kind, name, equivalents \\ nil) do
    equivalents = equivalents || [provider]

    equivalent_providers =
      equivalents
      |> Enum.map(& &1.id)
      |> Enum.sort()

    %{
      "from" => from.id,
      "kind" => kind,
      "name" => name,
      "provider" => provider.id,
      "provider_digest" => provider.elf.sha256,
      "equivalent_providers" => equivalent_providers
    }
  end

  defp file_record(provider) do
    elf = provider.elf

    %{
      "id" => provider.id,
      "source" => provider.source,
      "path" => provider.real_path,
      "aliases" => provider.paths,
      "sha256" => elf.sha256,
      "class" => elf.class,
      "architecture" => elf.architecture,
      "endianness" => elf.endianness,
      "interpreter" => elf.interpreter,
      "needed" => elf.needed,
      "soname" => elf.soname
    }
  end

  defp artifact_records(artifacts) do
    artifacts
    |> Enum.map(fn artifact ->
      %{
        "name" => artifact.name,
        "build_identity" => artifact.build_identity,
        "payload_identity" => artifact.payload_identity,
        "external_libraries" => Enum.sort(artifact.external_libraries)
      }
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp validate_tree_path(path, limits) do
    components = String.split(path, "/", trim: false)

    cond do
      not String.valid?(path) or String.contains?(path, <<0>>) ->
        {:error, "tree path is not valid UTF-8"}

      byte_size(path) > limits.path_bytes ->
        {:error, "tree path exceeds #{limits.path_bytes} bytes"}

      length(components) > limits.depth ->
        {:error, "tree path exceeds nesting depth #{limits.depth}"}

      Enum.any?(components, &(&1 in ["", ".", ".."])) ->
        {:error, "tree path is not normalized"}

      true ->
        :ok
    end
  end

  defp expected_class(architecture) when architecture in ~w(x86_64 aarch64 riscv64),
    do: "elf64"

  defp expected_class(architecture) when architecture in ~w(x86 arm riscv32), do: "elf32"
  defp expected_class(architecture), do: "unsupported-#{architecture}"

  defp full_digest?(value), do: is_binary(value) and String.match?(value, ~r/^[0-9a-f]{64}$/)

  defp absolute(root, ""), do: root
  defp absolute(root, relative), do: Path.join(root, relative)
  defp join_relative("", name), do: name
  defp join_relative(parent, name), do: parent <> "/" <> name
  defp display_path(""), do: "."
  defp display_path(path), do: path
end
