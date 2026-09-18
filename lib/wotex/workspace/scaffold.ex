defmodule Wotex.Workspace.Scaffold do
  @moduledoc """
  Scaffolds a new package the way the family's packages are laid out today:

    * `packages/<name>/`: a Mix library with the `WOTEX_PATH_DEPS` sibling
      switch (dev, test and docs only), Hex `files` limited to code,
      `README.md`, `CHANGELOG.md`, `LICENSE` and `NOTICE`, HexDocs extras
      from `docs/packages/<name>/` with source links through `source_url/2`
      at the `<name>-v<version>` tag, the standard full gate (`.check.exs`)
      with archive, application-free and boundary scripts, a `CLAUDE.md`
      package contract, a `README.md` with installation and development
      sections and the `git_ops` release configuration;
    * `docs/packages/<name>/{specs,plans,provenance}/` with a catalogue
      skeleton and a completion contract, following the catalogue path
      convention of `docs/README.md`;
    * the manifest entry in `tooling/packages.yaml`.

  Templates come from the repository itself: `LICENSE` from the root and
  `.check.exs`, `.credo.exs`, `.doctor.exs`, `.formatter.exs` and
  `coveralls.json` from `packages/wotex-coap`. The gate gains the
  `{:boundary, ...}` tool for the scaffolded boundary scan. Generated Elixir
  files are formatted with the package formatter settings.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest

  @template_package "wotex-coap"
  # The native tool block of a package gate, from its comment to `native_test`.
  @native_tools ~r/\n    # First-party C, C\+\+ and Rust code.*\{:native_test,[^}]*\},/s
  @name_pattern ~r/^[a-z][a-z0-9-]*$/
  @line_length 100
  @boundary_tool ~s|    {:boundary, command: "elixir bin/check_boundary.exs"},\n|
  @archive_tool "    {:archive,"

  @type option :: {:root, Path.t()} | {:depends_on, [String.t()]}

  @doc """
  Creates the package and returns the repository-relative paths written.
  Refuses when the package, its documentation tree or its manifest entry
  already exists.
  """
  @spec create(String.t(), [option()]) :: {:ok, [Path.t()]} | {:error, String.t()}
  def create(name, opts \\ []) do
    root = Keyword.get(opts, :root, Workspace.root())
    depends_on = Keyword.get(opts, :depends_on, ["wotex"])
    manifest_path = Path.join(root, "tooling/packages.yaml")

    with :ok <- check_name(name),
         {:ok, manifest} <- Manifest.load(manifest_path),
         :ok <- check_absent(name, manifest, root),
         :ok <- check_dependencies(depends_on, manifest),
         {:ok, templates} <- templates(root) do
      files = files(name, depends_on, transitive(depends_on, manifest), templates)
      Enum.each(files, fn {relative, content} -> write(root, relative, content) end)
      append_manifest(manifest_path, name, depends_on)

      case Manifest.load(manifest_path) do
        {:ok, _manifest} -> {:ok, ["tooling/packages.yaml" | Enum.map(files, &elem(&1, 0))]}
        {:error, message} -> {:error, "manifest invalid after append: #{message}"}
      end
    end
  end

  @doc "The OTP application name of a package: dashes become underscores."
  @spec app(String.t()) :: String.t()
  def app(name), do: String.replace(name, "-", "_")

  @doc """
  The module namespace of a package: `wotex-foo-bar` becomes `Wotex.FooBar`,
  any other name is camelized.
  """
  @spec namespace(String.t()) :: String.t()
  def namespace("wotex-" <> rest), do: "Wotex." <> Macro.camelize(String.replace(rest, "-", "_"))
  def namespace(name), do: Macro.camelize(app(name))

  @doc """
  The human-readable package name used for the Mix `name`, titles and
  prose: `wotex-foo-bar` becomes `Wotex Foo Bar`.
  """
  @spec title(String.t()) :: String.t()
  def title(name), do: Enum.map_join(String.split(name, "-"), " ", &String.capitalize/1)

  @doc "The manifest entry appended for a new package."
  @spec manifest_entry(String.t(), [String.t()]) :: String.t()
  def manifest_entry(name, depends_on) do
    "  #{name}:\n    app: #{app(name)}\n    depends_on: [#{Enum.join(depends_on, ", ")}]\n"
  end

  @doc """
  The package gate: the template gate without the template package's native
  tools (`native_format`, `native_lint`, `native_test`; a package with native
  code adds them together with its `native_check` suites) and with the
  `{:boundary, ...}` tool inserted before the archive tool. A template that
  already runs a boundary tool keeps it.
  """
  @spec gate(String.t()) :: {:ok, String.t()} | :error
  def gate(template) do
    template = Regex.replace(@native_tools, template, "")

    cond do
      template =~ "{:boundary," -> {:ok, template}
      String.contains?(template, @archive_tool) -> {:ok, insert_boundary(template)}
      true -> :error
    end
  end

  defp insert_boundary(template) do
    String.replace(template, @archive_tool, @boundary_tool <> @archive_tool, global: false)
  end

  defp check_name(name) do
    if is_binary(name) and Regex.match?(@name_pattern, name),
      do: :ok,
      else: {:error, "package name must match #{inspect(@name_pattern)}, got #{inspect(name)}"}
  end

  defp check_absent(name, manifest, root) do
    cond do
      Manifest.package?(name, manifest) ->
        {:error, "package #{name} is already in the manifest"}

      File.exists?(Path.join(root, "packages/#{name}")) ->
        {:error, "packages/#{name} exists"}

      File.exists?(Path.join(root, "docs/packages/#{name}")) ->
        {:error, "docs/packages/#{name} exists"}

      true ->
        :ok
    end
  end

  defp check_dependencies(depends_on, manifest) do
    case Enum.reject(depends_on, &Manifest.package?(&1, manifest)) do
      [] -> :ok
      unknown -> {:error, "unknown dependencies: #{Enum.join(unknown, ", ")}"}
    end
  end

  # The direct dependencies plus everything they depend on, in manifest order:
  # a consumer declares all of them for a `git:`/`sparse:` dependency.
  defp transitive(depends_on, manifest) do
    depends_on
    |> Enum.flat_map(&[&1 | Manifest.transitive_dependencies(&1, manifest)])
    |> Manifest.in_order(manifest)
  end

  defp templates(root) do
    sources = [
      license: "LICENSE",
      check: "packages/#{@template_package}/.check.exs",
      credo: "packages/#{@template_package}/.credo.exs",
      doctor: "packages/#{@template_package}/.doctor.exs",
      formatter: "packages/#{@template_package}/.formatter.exs",
      coveralls: "packages/#{@template_package}/coveralls.json"
    ]

    with {:ok, templates} <- read_templates(root, sources) do
      case gate(templates.check) do
        {:ok, check} ->
          {:ok, %{templates | check: check}}

        :error ->
          {:error, "template packages/#{@template_package}/.check.exs has no archive tool"}
      end
    end
  end

  defp read_templates(root, sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn {key, relative}, {:ok, acc} ->
      case File.read(Path.join(root, relative)) do
        {:ok, content} -> {:cont, {:ok, Map.put(acc, key, content)}}
        {:error, _reason} -> {:halt, {:error, "template #{relative} is missing"}}
      end
    end)
  end

  defp files(name, depends_on, transitive, templates) do
    namespace = namespace(name)
    package = "packages/#{name}"
    docs = "docs/packages/#{name}"
    module_path = Macro.underscore(namespace)

    bindings = %{
      "name" => name,
      "app" => app(name),
      "namespace" => namespace,
      "title" => title(name),
      "lib_path" => "lib/#{module_path}.ex",
      "test_path" => "test/#{module_path}_test.exs"
    }

    [
      {"#{package}/mix.exs", elixir(mix_exs(depends_on), bindings)},
      {"#{package}/.check.exs", templates.check},
      {"#{package}/.credo.exs", templates.credo},
      {"#{package}/.doctor.exs", templates.doctor},
      {"#{package}/.formatter.exs", templates.formatter},
      {"#{package}/coveralls.json", templates.coveralls},
      {"#{package}/config/config.exs", elixir(config(), bindings)},
      {"#{package}/CLAUDE.md", render(claude_md(depends_on), bindings)},
      {"#{package}/README.md", align_comments(render(readme(transitive), bindings))},
      {"#{package}/CHANGELOG.md", render(changelog(), bindings)},
      {"#{package}/LICENSE", templates.license},
      {"#{package}/NOTICE", render(notice(), bindings)},
      {"#{package}/#{bindings["lib_path"]}", elixir(library_module(), bindings)},
      {"#{package}/test/test_helper.exs", "ExUnit.start()\n"},
      {"#{package}/#{bindings["test_path"]}", elixir(test_module(), bindings)},
      {"#{package}/bin/check_archive.exs", elixir(check_archive(), bindings)},
      {"#{package}/bin/check_application_free.exs", elixir(check_application_free(), bindings)},
      {"#{package}/bin/check_boundary.exs", elixir(check_boundary(), bindings)},
      {"#{docs}/specs/catalogue.yaml", render(catalogue(), bindings)},
      {"#{docs}/plans/#{name}-completion.md", render(plan(), bindings)},
      {"#{docs}/provenance/.gitkeep", ""}
    ]
  end

  defp write(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp append_manifest(path, name, depends_on) do
    existing = File.read!(path)
    separator = if String.ends_with?(existing, "\n"), do: "", else: "\n"
    File.write!(path, existing <> separator <> manifest_entry(name, depends_on))
  end

  # Templates use `@@key@@` placeholders so that the Elixir interpolation in
  # the generated code needs no escaping here.

  defp render(template, bindings) do
    Enum.reduce(bindings, template, fn {key, value}, acc ->
      String.replace(acc, "@@#{key}@@", value)
    end)
  end

  defp elixir(template, bindings) do
    template
    |> render(bindings)
    |> Code.format_string!(line_length: @line_length)
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  defp mix_exs(depends_on) do
    siblings = Enum.map_join(depends_on, &~s|sibling(:#{app(&1)}, "#{&1}"),\n|)

    ~S"""
    defmodule @@namespace@@.MixProject do
      use Mix.Project

      @version "0.1.0"
      @source_url "https://github.com/wotex-project/wotex"
      @docs Path.expand("../../docs/packages/@@name@@", __DIR__)

      def project do
        [
          app: :@@app@@,
          name: "@@title@@",
          version: @version,
          elixir: "~> 1.18",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          aliases: aliases(),
          description: description(),
          package: package(),
          docs: docs(),
          source_url: @source_url,
          homepage_url: "https://wotex.io",
          test_ignore_filters: [~r{^test/support/}],
          test_coverage: [tool: ExCoveralls],
          dialyzer: dialyzer()
        ]
      end

      def application, do: [extra_applications: []]

      def cli do
        [
          preferred_envs: [
            coveralls: :test,
            "coveralls.detail": :test,
            "coveralls.html": :test,
            "coveralls.lcov": :test,
            "test.cover": :test
          ]
        ]
      end

      defp deps do
        [
    """ <>
      siblings <>
      ~S"""
          {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
          {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
          {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
          {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
          {:ex_doc, "~> 0.40", only: [:dev, :test, :docs], runtime: false},
          {:excoveralls, "~> 0.18", only: :test},
          {:git_ops, "~> 2.10", only: :dev, runtime: false},
          {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
        ]
      end
      """ <>
      if(depends_on == [], do: "", else: sibling_function()) <>
      ~S"""

        defp aliases do
          [
            setup: ["deps.get", "deps.compile"],
            lint: ["format --check-formatted", "credo --strict", "dialyzer"],
            "test.cover": ["coveralls"],
            package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
          ]
        end

        defp description do
          "Describe what @@name@@ owns in one sentence."
        end

        defp package do
          [
            licenses: ["Apache-2.0"],
            links: %{
              "GitHub" => @source_url,
              "Changelog" => "#{@source_url}/blob/main/packages/@@name@@/CHANGELOG.md",
              "Specifications" => "#{@source_url}/tree/main/docs/packages/@@name@@"
            },
            files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE NOTICE)
          ]
        end

        defp docs do
          [
            main: "readme",
            extras:
              ["README.md", "CHANGELOG.md"] ++
                Path.wildcard("#{@docs}/{specs,plans,decisions,provenance}/*.md"),
            groups_for_extras: [
              Specifications: ~r{docs/packages/@@name@@/specs/},
              "Completion contract": ~r{docs/packages/@@name@@/plans/},
              Decisions: ~r{docs/packages/@@name@@/decisions/},
              Provenance: ~r{docs/packages/@@name@@/provenance/}
            ],
            source_ref: "@@name@@-v#{@version}",
            source_url: @source_url,
            source_url_pattern: &source_url/2,
            formatters: ["html"]
          ]
        end

        # Links modules and the specification extras under the repository docs/
        # tree to their repository paths at this package's release tag.
        defp source_url(path, line) do
          root = Path.expand("../..", __DIR__)

          repository_path =
            path
            |> Path.expand(__DIR__)
            |> Path.relative_to(root)

          "#{@source_url}/blob/@@name@@-v#{@version}/#{repository_path}#L#{line}"
        end

        defp dialyzer do
          [
            plt_file: {:no_warn, "priv/plts/dialyxir.plt"},
            plt_add_apps: [:mix, :ex_unit],
            flags: [:error_handling, :missing_return, :underspecs, :extra_return]
          ]
        end
      end
      """
  end

  defp sibling_function do
    ~S"""

      # WOTEX_PATH_DEPS=1 is the only sibling switch and is allowed in the dev,
      # test and docs environments: unset means the Hex requirement, 1 means
      # the sibling checkout under packages/, loaded in :dev so that its own
      # switch guard accepts it.
      defp sibling(app, directory) do
        case System.get_env("WOTEX_PATH_DEPS") do
          nil ->
            {app, "~> 0.1.0"}

          "1" ->
            if Mix.env() in [:dev, :test, :docs] do
              {app, path: Path.expand("../#{directory}", __DIR__), env: :dev, override: true}
            else
              raise "WOTEX_PATH_DEPS is allowed only in development, test or docs"
            end

          _value ->
            raise "WOTEX_PATH_DEPS must be unset or equal to 1"
        end
      end
    """
  end

  defp config do
    ~S"""
    import Config

    if config_env() == :dev do
      config :git_ops,
        mix_project: Mix.Project.get!(),
        changelog_file: "CHANGELOG.md",
        repository_url: "https://github.com/wotex-project/wotex",
        version_tag_prefix: "@@name@@-v",
        manage_mix_version?: true,
        manage_readme_version: false,
        github_handle_lookup?: false,
        types: [
          chore: [hidden?: true],
          test: [hidden?: true],
          ci: [hidden?: true],
          build: [hidden?: true],
          style: [hidden?: true]
        ]
    end
    """
  end

  defp claude_md(depends_on) do
    siblings =
      case Enum.map(depends_on, &"`#{&1}`") do
        [] -> "It depends on no sibling package."
        [one] -> "It uses #{one} only through its public, documented API."
        names -> "It uses #{sentence(names)} only through their public, documented API."
      end

    String.replace(claude_md_template(), "@@siblings@@", siblings)
  end

  defp sentence([one]), do: one
  defp sentence(names), do: Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names)

  defp claude_md_template do
    ~S"""
    # @@title@@ package contract

    @@title@@ (`packages/@@name@@`, Hex `@@app@@`) owns <state what the package
    owns and what stays with the consumer>.
    @@siblings@@
    Repository-wide rules are in the root `CLAUDE.md`.

    ## Invariants

    - Loading the package starts no process and performs no runtime filesystem
      access; there is no application callback. Long-lived work is returned to
      the consumer as caller-configured child specifications.
    - No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
      framework integration or automatic network activity.
    - Pure values never consult application environment, clocks or random
      sources. Every public input boundary returns structured errors.
    - Use W3C Web of Things terms exactly; Thing Description 1.1 is the
      baseline. Package extension terms are never presented as W3C-defined.
    - Public functions have documentation and types. One module per `.ex` file.
      Tests use `@moduledoc false` followed by a blank line.

    ## Where things are

    - `@@lib_path@@`: the entry point, `@@namespace@@`.
    - `bin/check_archive.exs`: archive contents check;
      `bin/check_application_free.exs`: no application callback;
      `bin/check_boundary.exs`: consumer-neutral source scan (all in the full
      gate).
    - Specifications: `docs/packages/@@name@@/specs/` (`catalogue.yaml` owns
      status). Completion plan:
      `docs/packages/@@name@@/plans/@@name@@-completion.md`; provenance in
      `docs/packages/@@name@@/provenance/`.

    ## Working on this package

    | Tier | Command |
    | --- | --- |
    | 0 | `mix pkg @@name@@ test @@test_path@@`, or `mix impact @@namespace@@ version --run` |
    | 1 | `mix check.fast --package @@name@@` |
    | 2 | `mix check` (full gate here, fast gate in dependents) |

    The full gate alone is `mix pkg @@name@@ check --no-retry` (equivalently
    `WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/@@name@@`); it
    adds dependency audits, Doctor, docs, the 95% coverage floor, Dialyzer, the
    boundary scan, the archive check and the application-free check. Run
    `mix dialyzer.pkg @@name@@` in tier 1 when a typespec or inferred return
    type changed.

    Before changing a public function, list its callers with
    `mix refs @@namespace@@ fun` and the tests to run with
    `mix impact @@namespace@@ fun`. This package has no native build, software
    profile or container lane.
    """
  end

  defp readme(transitive) do
    # The package itself is named by placeholders until the bindings apply.
    packages = Enum.concat(Enum.map(transitive, &{app(&1), &1}), [{"@@app@@", "@@name@@"}])

    git_deps =
      Enum.map_join(packages, ",\n", fn {app, name} ->
        """
            {:#{app},
             git: "https://github.com/wotex-project/wotex.git",
             ref: @wotex_ref,
             sparse: "packages/#{name}",
             override: true}\
        """
      end)

    path_deps =
      Enum.map_join(packages, ",\n", fn {app, name} ->
        ~s|{:#{app}, path: "../wotex/packages/#{name}", override: true}|
      end)

    ~S"""
    # @@title@@

    **Describe what `@@name@@` owns in one sentence.**

    @@title@@ is a package of the WoTEx family. It is a development checkout
    with an unstable public API.

    ## Installation

    @@title@@ 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through Elixir
    1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
    in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
    No version is published on Hex yet. Once one is, depend on it as usual:

    ```elixir
    def deps do
      [
        {:@@app@@, "~> 0.1"}
      ]
    end
    ```

    Until then, depend on one commit of the
    [WoTEx repository](https://github.com/wotex-project/wotex) and select each
    package directory with `sparse:`. Declare every WoTEx package it needs at
    the same `ref` with `override: true`, as the
    [consumer guide](https://github.com/wotex-project/wotex/blob/main/docs/guides/consumer.md)
    describes:

    ```elixir
    @wotex_ref "<commit>"

    def deps do
      [
    @@git_deps@@
      ]
    end
    ```

    For local development with the repository checked out next to your project:

    ```elixir
    @@path_deps@@
    ```

    ## Development

    The [completion contract](../../docs/packages/@@name@@/plans/@@name@@-completion.md)
    and the specification catalogue
    (`docs/packages/@@name@@/specs/catalogue.yaml`) define the package's
    obligations. Local execution tracking is not part of the published
    contract.

    Run commands from the repository root; the
    [root README](https://github.com/wotex-project/wotex/blob/main/README.md)
    describes the workflow and validation tiers.

    ```console
    @@commands@@
    ```

    The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
    `packages/@@name@@`. It compiles with warnings as errors, checks the lock and
    unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
    Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
    tests with the 95% coverage floor (`mix coveralls`), Dialyzer, the boundary
    scan (`elixir bin/check_boundary.exs`) and `git diff --check`, then runs the
    archive check (`bin/check_archive.exs`) and the application-free check
    (`bin/check_application_free.exs`). This package has no native build,
    software profile or container lane.

    ## License

    @@title@@ is released under the
    [Apache License 2.0](https://github.com/wotex-project/wotex/blob/main/packages/@@name@@/LICENSE).
    """
    |> String.replace("@@git_deps@@", String.trim_trailing(git_deps))
    |> String.replace("@@path_deps@@", path_deps)
    |> String.replace("@@commands@@", commands())
  end

  # The commands are rendered with their placeholders, so the comment column
  # is aligned after the bindings are known; see `align_comments/1`.
  defp commands do
    Enum.join(
      [
        "mix pkg @@name@@ test @@test_path@@@@#@@one test file",
        "mix check.fast --package @@name@@@@#@@compile, format, Credo, tests",
        "mix pkg @@name@@ check --no-retry@@#@@full gate"
      ],
      "\n"
    )
  end

  defp align_comments(text) do
    lines = String.split(text, "\n")

    width =
      lines
      |> Enum.filter(&String.contains?(&1, "@@#@@"))
      |> Enum.map(&String.length(hd(String.split(&1, "@@#@@"))))
      |> Enum.max(fn -> 0 end)

    Enum.map_join(lines, "\n", fn line ->
      case String.split(line, "@@#@@") do
        [command, comment] -> String.pad_trailing(command, width) <> "  # " <> comment
        _other -> line
      end
    end)
  end

  defp changelog do
    ~S"""
    # Changelog

    All notable changes to `@@name@@` are recorded here by the release tooling.

    ## Unreleased
    """
  end

  defp notice do
    """
    @@title@@
    Copyright #{Date.utc_today().year} WoTEx contributors

    This package is part of the WoTEx package family and is licensed under the
    Apache License, Version 2.0 (see LICENSE).

    W3C Web of Things names and specification references identify external
    standards. They do not imply W3C endorsement or certification.
    """
  end

  defp library_module do
    ~S'''
    defmodule @@namespace@@ do
      @moduledoc """
      Entry point of `@@name@@`.
      """

      @version Mix.Project.config()[:version]

      @doc "The package version."
      @spec version() :: String.t()
      def version, do: @version
    end
    '''
  end

  defp test_module do
    ~S"""
    defmodule @@namespace@@Test do
      @moduledoc false

      use ExUnit.Case, async: true

      test "reports the package version" do
        assert @@namespace@@.version() == "0.1.0"
      end
    end
    """
  end

  defp check_archive do
    ~S"""
    # Builds the Hex archive without sibling path dependencies and verifies
    # that it ships code, README.md, CHANGELOG.md, LICENSE and NOTICE only.
    # Runs in the full gate: `mix run --no-start bin/check_archive.exs`.

    defmodule @@namespace@@.Check.Archive do
      @moduledoc false

      @required ~w(mix.exs README.md CHANGELOG.md LICENSE NOTICE)
      @forbidden ~w(docs test bin config .check.exs .credo.exs .doctor.exs coveralls.json CLAUDE.md)

      @spec main() :: :ok
      def main do
        version = Mix.Project.config()[:version]
        suffix = Integer.to_string(System.unique_integer([:positive]))
        temporary = Path.join(System.tmp_dir!(), "@@app@@-archive-" <> suffix)
        File.mkdir_p!(temporary)
        archive = Path.join(temporary, "@@app@@-#{version}.tar")

        result =
          try do
            build!(archive)
            verify!(files(archive, temporary))
            {:ok, sha256(archive)}
          catch
            :throw, {:archive, message} -> {:error, message}
          after
            File.rm_rf!(temporary)
          end

        case result do
          {:ok, digest} ->
            IO.puts("archive sha256: #{digest}")
            IO.puts("archive check passed")
            :ok

          {:error, message} ->
            IO.puts(:stderr, "archive check failed: " <> message)
            System.halt(1)
        end
      end

      defp build!(archive) do
        {output, status} =
          System.cmd("mix", ["hex.build", "--output", archive],
            env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}],
            stderr_to_stdout: true
          )

        IO.write(output)
        if status != 0, do: throw({:archive, "mix hex.build exited with #{status}"})
      end

      defp files(archive, temporary) do
        :ok = :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(temporary))
        contents = String.to_charlist(Path.join(temporary, "contents.tar.gz"))
        {:ok, entries} = :erl_tar.table(contents, [:compressed])
        Enum.map(entries, &to_string/1)
      end

      defp verify!(files) do
        missing = Enum.reject(@required, &(&1 in files))
        shipped = Enum.filter(files, &forbidden?/1)
        if missing != [], do: throw({:archive, "archive lacks " <> Enum.join(missing, ", ")})
        if shipped != [], do: throw({:archive, "archive ships " <> Enum.join(shipped, ", ")})
        :ok
      end

      defp forbidden?(file) do
        Enum.any?(@forbidden, &(file == &1 or String.starts_with?(file, &1 <> "/")))
      end

      defp sha256(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
    end

    @@namespace@@.Check.Archive.main()
    """
  end

  defp check_application_free do
    ~S"""
    # The package declares no application callback, and starting its
    # application starts no process of its own. Runs in the full gate:
    # `mix run --no-start bin/check_application_free.exs`.

    defmodule @@namespace@@.Check.ApplicationFree do
      @moduledoc false

      @spec main() :: :ok
      def main do
        case Application.load(:@@app@@) do
          :ok -> :ok
          {:error, {:already_loaded, :@@app@@}} -> :ok
        end

        unless Application.spec(:@@app@@, :mod) in [nil, []] do
          IO.puts(:stderr, "@@app@@ declares an application callback")
          System.halt(1)
        end

        {:ok, _started} = Application.ensure_all_started(:@@app@@)
        IO.puts("application-free check passed")
        :ok
      end
    end

    @@namespace@@.Check.ApplicationFree.main()
    """
  end

  defp check_boundary do
    ~S"""
    # Consumer-neutral source scan. Runs with Elixir alone from the package
    # directory, and in the full gate: `elixir bin/check_boundary.exs`.

    defmodule @@namespace@@.Check.Boundary do
      @moduledoc false

      @library ~r{(Application\.start\(|use Application|use Ash|use Phoenix|Ecto\.Repo|Oban\.)}
      @umbrella ~r{apps_path[[:space:]]*:}
      @machine_path ~r{([/]Users[/]|[/]home[/])}
      @excluded ~w(.git .elixir_ls _build cover deps doc priv/plts)

      @spec main() :: :ok
      def main do
        scan(["lib", "test", "mix.exs"], @library, "consumer-neutral library boundary violation")
        scan(["mix.exs"], @umbrella, "umbrella configuration is forbidden")
        scan(["."], @machine_path, "machine-local path found")
        IO.puts("boundary scan passed")
      end

      defp scan(roots, pattern, message) do
        hits = roots |> Enum.flat_map(&files/1) |> Enum.flat_map(&matches(&1, pattern))

        if hits != [] do
          Enum.each(hits, &IO.puts/1)
          IO.puts(:stderr, message)
          System.halt(1)
        end
      end

      defp files(path) do
        cond do
          path in @excluded -> []
          File.dir?(path) -> path |> File.ls!() |> Enum.sort() |> Enum.flat_map(&files(child(path, &1)))
          File.regular?(path) -> [path]
          true -> []
        end
      end

      defp child(".", name), do: name
      defp child(path, name), do: Path.join(path, name)

      defp matches(path, pattern) do
        with {:ok, content} <- File.read(path),
             true <- String.valid?(content) do
          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _number} -> Regex.match?(pattern, line) end)
          |> Enum.map(fn {line, number} -> "#{path}:#{number}: #{line}" end)
        else
          _other -> []
        end
      end
    end

    @@namespace@@.Check.Boundary.main()
    """
  end

  # Catalogue paths follow docs/README.md: `docs/...` is relative to
  # docs/packages/<name>/, any other path to packages/<name>/.
  defp catalogue do
    ~S"""
    # Normative status owner of @@name@@. A path that starts with docs/ is
    # relative to docs/packages/@@name@@/; any other path is relative to
    # packages/@@name@@/. Add one entry per specification, for example:
    #
    #   - id: "XYZ.01"
    #     version: "0.1.0"
    #     path: "docs/specs/XYZ.01-title.md"
    #     implementation_status: "planned"
    schema_version: "1.1.0"
    package: "@@app@@"
    completion_plan: "docs/plans/@@name@@-completion.md"
    specifications: []
    """
  end

  defp plan do
    ~S"""
    # @@title@@ completion contract

    Plan revision `1.0.0`. This plan is a versioned contract: a changed
    obligation needs a new plan revision. Execution status stays in
    `docs/tasks/local/`.

    ## Obligations

    1. State what the package owns and the standards it claims, pinning the
       exact revision and executable evidence for every claim.
    2. Add each specification under `specs/` and record its version and
       `implementation_status` in `specs/catalogue.yaml`.

    ## Evidence

    The full gate, `mix pkg @@name@@ check --no-retry` from the repository
    root.
    """
  end
end
