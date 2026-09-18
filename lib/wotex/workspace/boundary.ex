defmodule Wotex.Workspace.Boundary do
  @moduledoc """
  The sibling-API gate: a package may use only the public, documented API of
  a sibling package. A reference to a sibling module with `@moduledoc false`
  or to a function with `@doc false` compiles but is a boundary violation.

  For a package the gate:

    1. compiles the package with `WOTEX_PATH_DEPS=1 MIX_ENV=test mix compile`
       so that every sibling's beams exist under
       `packages/<name>/_build/test/lib/<sibling_app>/ebin`;
    2. reads the docs chunk of every sibling beam (`Code.fetch_docs/1`) and
       collects the hidden modules and hidden functions;
    3. parses every `lib/**/*.ex` and `test/**/*.exs` of the package and
       resolves remote calls, captures and module references against the
       `alias` directives in scope;
    4. reports every reference to a hidden sibling module or function.

  ## Limitations

  The analysis is syntactic and conservative. It resolves only references
  whose module is written out or reachable through a plain, `as:` or
  multi-alias directive in the same lexical scope. References built with
  `__MODULE__`, `Module.concat/1`, `apply/3`, `import`, macros that expand to
  sibling calls or modules stored in variables are not resolved and are not
  reported. A parse failure is reported as a finding so that it is not
  silently skipped.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Runner

  defmodule Index do
    @moduledoc """
    What is known about the sibling modules: every module, the hidden
    modules and the hidden `{module, function, arity}` triples.
    """

    @typedoc "A module name without the `Elixir.` prefix, such as `\"Wotex.Runtime\"`."
    @type module_name :: String.t()

    @type t :: %__MODULE__{
            modules: MapSet.t(module_name()),
            hidden_modules: MapSet.t(module_name()),
            hidden_functions: MapSet.t({module_name(), atom(), non_neg_integer()})
          }

    defstruct modules: MapSet.new(), hidden_modules: MapSet.new(), hidden_functions: MapSet.new()
  end

  @type finding :: %{file: Path.t(), line: non_neg_integer(), message: String.t()}

  @type option :: {:compile, boolean()}

  @doc """
  Runs the gate for package `name`. Returns the findings (an empty list is a
  pass) or an error when the package does not compile.
  """
  @spec run(String.t(), Manifest.t(), Path.t(), [option()]) ::
          {:ok, [finding()]} | {:error, String.t()}
  def run(name, %Manifest{} = manifest \\ Manifest.load!(), root \\ Workspace.root(), opts \\ []) do
    package_path = Manifest.absolute_path(name, manifest, root)

    with :ok <- compile(name, package_path, opts) do
      dirs =
        for sibling <- Manifest.transitive_dependencies(name, manifest),
            do: ebin_dir(package_path, Manifest.fetch!(sibling, manifest).app)

      index = index(dirs)
      {:ok, analyze_package(package_path, root, index)}
    end
  end

  @doc "The directory that holds a compiled sibling's beams."
  @spec ebin_dir(Path.t(), String.t()) :: Path.t()
  def ebin_dir(package_path, sibling_app),
    do: Path.join([package_path, "_build/test/lib", sibling_app, "ebin"])

  @doc "Indexes every `*.beam` in the given directories."
  @spec index([Path.t()]) :: Index.t()
  def index(ebin_dirs) do
    ebin_dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "Elixir.*.beam")))
    |> Enum.reduce(%Index{}, fn beam, index -> add(index, index_beam(beam)) end)
  end

  @doc """
  Reads one beam's docs chunk: `{module, hidden?, hidden_functions}`. A beam
  without a docs chunk counts as public.
  """
  @spec index_beam(Path.t()) :: {Index.module_name(), boolean(), [{atom(), non_neg_integer()}]}
  def index_beam(beam) do
    module = String.replace_prefix(Path.basename(beam, ".beam"), "Elixir.", "")

    case Code.fetch_docs(beam) do
      {:docs_v1, _anno, _language, _format, module_doc, metadata, docs} ->
        hidden? = module_doc == :hidden or Map.get(metadata, :hidden) == true

        hidden_functions =
          for {{kind, name, arity}, _anno, _signature, :hidden, _meta} <- docs,
              kind in [:function, :macro],
              do: {name, arity}

        {module, hidden?, hidden_functions}

      {:error, _reason} ->
        {module, false, []}
    end
  end

  @doc """
  Adds a module to the index. Exposed for tests that build fixture indexes.
  """
  @spec add(Index.t(), {Index.module_name(), boolean(), [{atom(), non_neg_integer()}]}) ::
          Index.t()
  def add(%Index{} = index, {module, hidden?, hidden_functions}) do
    %Index{
      modules: MapSet.put(index.modules, module),
      hidden_modules:
        if(hidden?, do: MapSet.put(index.hidden_modules, module), else: index.hidden_modules),
      hidden_functions:
        Enum.reduce(hidden_functions, index.hidden_functions, fn {name, arity}, set ->
          MapSet.put(set, {module, name, arity})
        end)
    }
  end

  @doc """
  Analyzes every `lib/**/*.ex` and `test/**/*.exs` below `package_path`.
  File names in findings are relative to `root`.
  """
  @spec analyze_package(Path.t(), Path.t(), Index.t()) :: [finding()]
  def analyze_package(package_path, root, %Index{} = index) do
    files =
      Path.wildcard(Path.join(package_path, "lib/**/*.ex")) ++
        Path.wildcard(Path.join(package_path, "test/**/*.exs"))

    Enum.flat_map(files, fn file ->
      analyze(File.read!(file), Path.relative_to(file, root), index)
    end)
  end

  @doc """
  Analyzes one source file's text and returns its findings.
  """
  @spec analyze(String.t(), Path.t(), Index.t()) :: [finding()]
  def analyze(source, file, %Index{} = index) do
    case Code.string_to_quoted(source, file: file, columns: false) do
      {:ok, ast} ->
        {_aliases, {_file, _index, findings}} = walk(ast, %{}, {file, index, []})
        Enum.uniq(Enum.reverse(findings))

      {:error, {meta, message, token}} ->
        [
          %{
            file: file,
            line: line(meta),
            message: "cannot be parsed: #{format_parse_error(message, token)}"
          }
        ]
    end
  end

  @doc "Formats a finding as `file:line: message`."
  @spec format(finding()) :: String.t()
  def format(%{file: file, line: line, message: message}), do: "#{file}:#{line}: #{message}"

  # Compilation

  defp compile(name, package_path, opts) do
    if Keyword.get(opts, :compile, true) do
      case Runner.run(package_path, ["compile"], mix_env: "test") do
        0 -> :ok
        status -> {:error, "packages/#{name}: mix compile exited with status #{status}"}
      end
    else
      :ok
    end
  end

  # AST walk. `aliases` maps an alias atom to the module parts it stands for
  # and only flows between the statements of one block. The accumulator is
  # `{file, index, findings}`.

  defp walk({:__block__, _meta, statements}, aliases, acc) do
    Enum.reduce(statements, {aliases, acc}, fn statement, {aliases, acc} ->
      walk(statement, aliases, acc)
    end)
  end

  defp walk({:alias, meta, args}, aliases, acc), do: register_alias(args, meta, aliases, acc)

  defp walk({:&, meta, [{:/, _, [{{:., _, [target, fun]}, _, []}, arity]}]}, aliases, acc)
       when is_atom(fun) and is_integer(arity) do
    {aliases, check_call(target, fun, arity, meta, aliases, acc)}
  end

  # `left |> Mod.fun(args)` is analyzed as `Mod.fun(left, args)` so that the
  # arity matches the function actually called.
  defp walk({:|>, _meta, [left, right]}, aliases, acc) do
    piped =
      try do
        Macro.pipe(left, right, 0)
      rescue
        ArgumentError -> nil
      end

    case piped do
      nil -> {aliases, descend([left, right], aliases, acc)}
      call -> walk(call, aliases, acc)
    end
  end

  defp walk({{:., _dot, [target, fun]}, meta, args}, aliases, acc)
       when is_atom(fun) and is_list(args) do
    acc = check_call(target, fun, length(args), meta, aliases, acc)
    acc = if aliases_node?(target), do: acc, else: descend(target, aliases, acc)
    {aliases, descend(args, aliases, acc)}
  end

  defp walk({:__aliases__, meta, parts}, aliases, acc) do
    {aliases, check_module(parts, meta, aliases, acc)}
  end

  defp walk({form, _meta, args}, aliases, acc) when is_list(args) do
    acc = descend(form, aliases, acc)
    {aliases, descend(args, aliases, acc)}
  end

  defp walk({left, right}, aliases, acc) do
    {aliases, right |> descend(aliases, descend(left, aliases, acc))}
  end

  defp walk(list, aliases, acc) when is_list(list) do
    {aliases, Enum.reduce(list, acc, &descend(&1, aliases, &2))}
  end

  defp walk(_literal, aliases, acc), do: {aliases, acc}

  defp descend(node, aliases, acc) do
    {_aliases, acc} = walk(node, aliases, acc)
    acc
  end

  # alias A.B.C and alias A.B.C, as: D
  defp register_alias([{:__aliases__, _, parts} | rest], meta, aliases, acc) do
    case resolve_parts(parts, aliases) do
      nil ->
        {aliases, acc}

      resolved ->
        name = alias_name(rest, parts)
        {Map.put(aliases, name, resolved), check_resolved(resolved, meta, acc)}
    end
  end

  # alias A.B.{C, D.E}
  defp register_alias(
         [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children} | _rest],
         meta,
         aliases,
         acc
       ) do
    case resolve_parts(base, aliases) do
      nil ->
        {aliases, acc}

      resolved_base ->
        Enum.reduce(children, {aliases, acc}, fn
          {:__aliases__, _, parts}, {aliases, acc} when is_list(parts) ->
            resolved = resolved_base ++ parts
            {Map.put(aliases, List.last(parts), resolved), check_resolved(resolved, meta, acc)}

          _other, state ->
            state
        end)
    end
  end

  defp register_alias(_args, _meta, aliases, acc), do: {aliases, acc}

  defp alias_name([opts | _], parts) when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, [name]} when is_atom(name) -> name
      _other -> List.last(parts)
    end
  end

  defp alias_name(_rest, parts), do: List.last(parts)

  defp check_module(parts, meta, aliases, acc) do
    case resolve_parts(parts, aliases) do
      nil -> acc
      resolved -> check_resolved(resolved, meta, acc)
    end
  end

  defp check_resolved(resolved, meta, {file, index, findings} = acc) do
    module = module_name(resolved)

    if MapSet.member?(index.hidden_modules, module) do
      {file, index, [finding(file, meta, "#{module} is not public API") | findings]}
    else
      acc
    end
  end

  # The printed name of module parts, without the `Elixir` prefix and
  # without creating an atom for a module this VM never loads.
  defp module_name(parts) do
    parts
    |> Enum.map(&Atom.to_string/1)
    |> Enum.reject(&(&1 == "Elixir"))
    |> Enum.map_join(".", &String.replace_prefix(&1, "Elixir.", ""))
  end

  defp check_call(
         {:__aliases__, _, parts},
         fun,
         arity,
         meta,
         aliases,
         {file, index, findings} = acc
       ) do
    case resolve_parts(parts, aliases) do
      nil ->
        acc

      resolved ->
        module = module_name(resolved)

        hidden? =
          MapSet.member?(index.hidden_modules, module) or
            MapSet.member?(index.hidden_functions, {module, fun, arity})

        if hidden? do
          message = "#{module}.#{fun}/#{arity} is not public API"
          {file, index, [finding(file, meta, message) | findings]}
        else
          acc
        end
    end
  end

  defp check_call(_target, _fun, _arity, _meta, _aliases, acc), do: acc

  defp resolve_parts([first | rest], aliases) when is_atom(first) do
    Map.get(aliases, first, [first]) ++ rest
  end

  defp resolve_parts(_parts, _aliases), do: nil

  defp aliases_node?({:__aliases__, _, _}), do: true
  defp aliases_node?(_other), do: false

  defp finding(file, meta, message), do: %{file: file, line: line(meta), message: message}

  defp line(meta) when is_list(meta), do: Keyword.get(meta, :line, 0)
  defp line(_meta), do: 0

  defp format_parse_error({prefix, suffix}, token), do: "#{prefix}#{token}#{suffix}"
  defp format_parse_error(message, token), do: "#{message}#{token}"
end
