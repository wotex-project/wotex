defmodule Wotex.Workspace.NativeBench do
  @moduledoc """
  One entry of a package's `native_bench` list in `tooling/packages.yaml`: a
  benchmark of the package's C, C++ or Rust code that `mix native.bench`
  runs and reports in `bench/output/native-<id>.md`.

      native_bench:
        - bench: output_queue          # id, unique within the package
          kind: nanobench              # nanobench, criterion or elixir
          title: Bounded output queue  # the report's heading
          description: >-              # the report's first paragraph
            Admission and credited flush of normal envelopes.
          requires: [linux]            # host requirements: linux, docker
          env:                         # environment of the benchmark process
            NAME: "{package}/priv/fixtures"
          compile:                     # nanobench: files and their compile flags
            - files: [bench/native/output_queue.cpp]
              flags: [-std=c++17, "-I{package}/priv/native"]
            - files: [priv/native/output.c]
              flags: [-std=c11, "-I{package}/priv/native"]
          link: [-lm]                  # nanobench: link flags

  The kind fixes where the benchmark lives in the package:

    * `nanobench`: the C++ driver `bench/native/<id>.cpp`, compiled with the
      translation units `compile` names (C, C++, vendored or first-party;
      the driver must be among them) and linked with the vendored nanobench
      (`tooling/native/nanobench`). `link` adds linker flags. First-party C
      is included from the driver inside `extern "C"`.
    * `criterion`: the Cargo crate `bench/native/<id>/`, a crate of its own
      with a committed `Cargo.lock`, run with `cargo bench`. It reaches the
      shipped code through a path dependency on a library target or, for a
      binary-only crate, by including its modules with `#[path]`.
    * `elixir`: the script `bench/native/<id>_bench.exs`, run with `mix run`
      after the package's `native_task` built the workspace named by
      `--workspace`. The package must declare a `native_task`.

  Strings in `env`, `compile` flags and `link` take the placeholders of
  `native_check` (`Wotex.Workspace.NativeSuite`): `{package}`, `{root}`,
  `{scratch}` (a directory emptied before each run) and, for the `elixir`
  kind only, `{workspace}`. A flag `pkg-config:NAME` expands to `pkg-config
  --cflags NAME` in `compile` and to `pkg-config --libs NAME` in `link`.

  A benchmark that requires only Linux (optionally with `tun`, which gives
  the container a tun device and `CAP_NET_ADMIN`) runs in the Linux
  container of the native checks on another host with Docker (`nanobench` and `elixir`; the
  container has no Rust toolchain). There is no `container` key: the suite
  images carry no Elixir, and a `nanobench` driver compiles package sources
  only.
  """

  alias Wotex.Workspace.Affected
  alias Wotex.Workspace.NativeSuite

  @kinds %{"nanobench" => :nanobench, "criterion" => :criterion, "elixir" => :elixir}
  @common ~w(bench kind title description requires env)
  @keys %{nanobench: @common ++ ~w(compile link), criterion: @common, elixir: @common}
  @nanobench "tooling/native/nanobench"

  @type kind :: :nanobench | :criterion | :elixir

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          title: String.t(),
          description: String.t(),
          requires: [String.t()],
          env: [{String.t(), String.t()}],
          compile: [NativeSuite.compile()],
          link: [String.t()]
        }

  @enforce_keys [:id, :kind, :title, :description]
  defstruct [:id, :kind, :title, :description, requires: [], env: [], compile: [], link: []]

  @doc "The kinds a benchmark may declare."
  @spec kinds() :: [String.t()]
  def kinds, do: Enum.sort(Map.keys(@kinds))

  @doc "The repository-relative directory of the vendored nanobench header."
  @spec nanobench_dir() :: Path.t()
  def nanobench_dir, do: @nanobench

  @doc """
  The flags every `nanobench` translation unit is compiled with, before the
  flags of its `compile` rule: optimisation, `NDEBUG` and nanobench as a
  system include directory.
  """
  @spec default_flags() :: [String.t()]
  def default_flags, do: ["-O2", "-DNDEBUG", "-isystem{root}/#{@nanobench}"]

  @doc """
  The package-relative path of the benchmark's source: the driver, the
  crate manifest or the script.
  """
  @spec source(t()) :: Path.t()
  def source(%__MODULE__{kind: :nanobench, id: id}), do: "bench/native/#{id}.cpp"
  def source(%__MODULE__{kind: :criterion, id: id}), do: "bench/native/#{id}/Cargo.toml"
  def source(%__MODULE__{kind: :elixir, id: id}), do: "bench/native/#{id}_bench.exs"

  @doc "The file name of the benchmark's report in `bench/output/`."
  @spec report(t()) :: String.t()
  def report(%__MODULE__{id: id}), do: "native-#{id}.md"

  @doc "The name of the compile-only suite that gives clang-tidy the driver's compile commands."
  @spec suite_name(t()) :: String.t()
  def suite_name(%__MODULE__{id: id}), do: "bench-#{id}"

  @doc """
  One compile-only `native_check` suite per `nanobench` benchmark, so that
  `mix native.lint --tidy` analyses the first-party translation units below
  `bench/native/` with the benchmark's flags. The package sources a driver
  includes are covered by the package's own suites.
  """
  @spec tidy_suites([t()]) :: [NativeSuite.t()]
  def tidy_suites(benches) do
    for %__MODULE__{kind: :nanobench} = bench <- benches,
        rules = bench_rules(bench.compile),
        rules != [] do
      %NativeSuite{name: suite_name(bench), requires: bench.requires, compile: rules}
    end
  end

  defp bench_rules(rules) do
    for rule <- rules,
        files = Enum.filter(rule.files, &String.starts_with?(&1, "bench/native/")),
        files != [],
        do: %{files: files, flags: default_flags() ++ rule.flags}
  end

  @doc "Parses the `native_bench` value of package `package` (a list, or `nil`)."
  @spec parse_all(String.t(), term()) :: {:ok, [t()]} | {:error, String.t()}
  def parse_all(_, nil), do: {:ok, []}

  def parse_all(package, benches) when is_list(benches) do
    with {:ok, parsed} <- collect(benches, &parse(package, &1)), do: check_unique(package, parsed)
  end

  def parse_all(package, _), do: {:error, "package #{package}: native_bench must be a list"}

  @doc "Parses one benchmark mapping."
  @spec parse(String.t(), term()) :: {:ok, t()} | {:error, String.t()}
  def parse(package, %{"bench" => id} = entry) when is_binary(id) do
    where = "package #{package}, native_bench #{id}"

    with :ok <- check_id(where, id),
         {:ok, kind} <- kind(where, entry["kind"]),
         :ok <- NativeSuite.known_keys(where, entry, @keys[kind]),
         {:ok, title} <- text(where, "title", entry["title"]),
         {:ok, description} <- text(where, "description", entry["description"]),
         {:ok, requires} <- NativeSuite.parse_requires(where, Map.get(entry, "requires", [])),
         {:ok, env} <- NativeSuite.parse_env(where, Map.get(entry, "env", %{})),
         {:ok, compile} <- NativeSuite.parse_compile(where, Map.get(entry, "compile", [])),
         {:ok, link} <- NativeSuite.parse_strings(where, "link", Map.get(entry, "link", [])),
         bench = %__MODULE__{
           id: id,
           kind: kind,
           title: title,
           description: description,
           requires: requires,
           env: env,
           compile: compile,
           link: link
         },
         :ok <- check_driver(where, bench),
         :ok <- check_placeholders(where, bench) do
      {:ok, bench}
    end
  end

  def parse(package, _),
    do: {:error, "package #{package}: every native_bench entry needs a bench id"}

  defp check_id(where, id) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, id),
      do: :ok,
      else: {:error, "#{where}: the bench id must be lowercase letters, digits and underscores"}
  end

  defp kind(where, kind) do
    case Map.fetch(@kinds, kind) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, "#{where}: kind must be one of #{Enum.join(kinds(), ", ")}"}
    end
  end

  defp text(where, key, value) do
    case is_binary(value) && String.trim(value) do
      text when text in [false, ""] -> {:error, "#{where}: #{key} must be a non-empty string"}
      text -> {:ok, text}
    end
  end

  defp check_driver(where, %__MODULE__{kind: :nanobench} = bench) do
    driver = source(bench)

    if Enum.any?(bench.compile, fn rule ->
         Enum.any?(rule.files, &Affected.glob_match?(&1, driver))
       end),
       do: :ok,
       else: {:error, "#{where}: compile must include the driver #{driver}"}
  end

  defp check_driver(_, _), do: :ok

  defp check_placeholders(where, bench) do
    strings =
      Enum.map(bench.env, &elem(&1, 1)) ++ Enum.flat_map(bench.compile, & &1.flags) ++ bench.link

    used = NativeSuite.placeholders_in(strings)

    cond do
      (unknown = used -- NativeSuite.placeholders()) != [] ->
        {:error, "#{where}: unknown placeholder(s) #{Enum.map_join(unknown, ", ", &"{#{&1}}")}"}

      "workspace" in used and bench.kind != :elixir ->
        {:error, "#{where}: {workspace} is available to the elixir kind only"}

      true ->
        :ok
    end
  end

  defp check_unique(package, benches) do
    ids = Enum.map(benches, & &1.id)

    case ids -- Enum.uniq(ids) do
      [] -> {:ok, benches}
      [duplicate | _] -> {:error, "package #{package}: duplicate native_bench #{duplicate}"}
    end
  end

  defp collect(list, fun) do
    list
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case fun.(entry) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end
end
