defmodule Wotex.Workspace.Scaffold do
  @moduledoc """
  Scaffolds a new package: `packages/<name>` (Mix project with the
  `WOTEX_PATH_DEPS` sibling switch, gate configuration, governance files),
  `docs/packages/<name>/{specs,plans,provenance}` with a catalogue skeleton
  and a manifest entry in `tooling/packages.yaml`.

  Templates come from the repository itself: `LICENSE` from the root and
  `.check.exs`, `.credo.exs`, `.formatter.exs` and `coveralls.json` from
  `packages/wotex-coap`.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest

  @template_package "wotex-coap"
  @name_pattern ~r/^[a-z][a-z0-9-]*$/

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
      files = files(name, depends_on, templates)
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

  @doc "The manifest entry appended for a new package."
  @spec manifest_entry(String.t(), [String.t()]) :: String.t()
  def manifest_entry(name, depends_on) do
    "  #{name}:\n    app: #{app(name)}\n    depends_on: [#{Enum.join(depends_on, ", ")}]\n"
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

  defp templates(root) do
    sources = [
      license: "LICENSE",
      check: "packages/#{@template_package}/.check.exs",
      credo: "packages/#{@template_package}/.credo.exs",
      formatter: "packages/#{@template_package}/.formatter.exs",
      coveralls: "packages/#{@template_package}/coveralls.json"
    ]

    Enum.reduce_while(sources, {:ok, %{}}, fn {key, relative}, {:ok, acc} ->
      case File.read(Path.join(root, relative)) do
        {:ok, content} -> {:cont, {:ok, Map.put(acc, key, content)}}
        {:error, _reason} -> {:halt, {:error, "template #{relative} is missing"}}
      end
    end)
  end

  defp files(name, depends_on, templates) do
    app = app(name)
    namespace = namespace(name)
    package = "packages/#{name}"
    docs = "docs/packages/#{name}"
    lib_path = Path.join(package, "lib/" <> Macro.underscore(namespace) <> ".ex")

    [
      {"#{package}/mix.exs", mix_exs(name, app, namespace, depends_on)},
      {"#{package}/.check.exs", templates.check},
      {"#{package}/.credo.exs", templates.credo},
      {"#{package}/.formatter.exs", templates.formatter},
      {"#{package}/coveralls.json", templates.coveralls},
      {"#{package}/CLAUDE.md", claude_md(name, namespace)},
      {"#{package}/README.md", readme(name, app, namespace)},
      {"#{package}/CHANGELOG.md", changelog(name)},
      {"#{package}/LICENSE", templates.license},
      {"#{package}/NOTICE", notice(name)},
      {lib_path, library_module(name, namespace)},
      {"#{package}/test/test_helper.exs", "ExUnit.start()\n"},
      {"#{package}/test/#{app}_test.exs", test_module(namespace)},
      {"#{package}/bin/check_archive.exs", check_archive(app, namespace)},
      {"#{package}/bin/check_application_free.exs", check_application_free(app, namespace)},
      {"#{docs}/specs/catalogue.yaml", catalogue(name, app)},
      {"#{docs}/plans/#{name}-completion.md", plan(name)},
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

  # Templates

  defp mix_exs(name, app, namespace, depends_on) do
    sibling_deps =
      Enum.map_join(depends_on, "\n", fn dependency ->
        ~s|      sibling(:#{app(dependency)}, "#{dependency}"),|
      end)

    """
    defmodule #{namespace}.MixProject do
      use Mix.Project

      @version "0.1.0"
      @source_url "https://github.com/wotex-project/wotex"

      def project do
        [
          app: :#{app},
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
          dialyzer: dialyzer(),
          name: "#{namespace}"
        ]
      end

      def application, do: [extra_applications: []]

      def cli do
        [
          preferred_envs: [
            coveralls: :test,
            "coveralls.detail": :test,
            "coveralls.html": :test,
            "coveralls.lcov": :test
          ]
        ]
      end

      defp deps do
        [
    #{sibling_deps}
          {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
          {:git_ops, "~> 2.10", only: :dev, runtime: false},
          {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
          {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
          {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
          {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false},
          {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
          {:doctest_formatter, "~> 0.4", only: [:dev, :test], runtime: false},
          {:excoveralls, "~> 0.18", only: :test},
          {:stream_data, "~> 1.3", only: :test}
        ]
      end

      # WOTEX_PATH_DEPS=1 is the only sibling switch: unset means the Hex
      # requirement, 1 means the sibling checkout under packages/.
      defp sibling(app, name) do
        case System.get_env("WOTEX_PATH_DEPS") do
          nil -> {app, "~> 0.1.0"}
          "1" -> {app, path: Path.expand("../" <> name, __DIR__), override: true}
          _value -> raise "WOTEX_PATH_DEPS must be unset or equal to 1"
        end
      end

      defp aliases do
        [
          setup: ["deps.get", "deps.compile"],
          lint: ["format --check-formatted", "credo --strict", "dialyzer"],
          package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build",
          "test.cover": ["coveralls"]
        ]
      end

      defp description do
        "#{namespace}: describe what this package owns"
      end

      defp package do
        [
          name: "#{app}",
          licenses: ["Apache-2.0"],
          links: %{
            "GitHub" => @source_url,
            "Changelog" => @source_url <> "/blob/main/packages/#{name}/CHANGELOG.md",
            "Specifications" => @source_url <> "/tree/main/docs/packages/#{name}",
            "Documentation" => "https://hexdocs.pm/#{app}",
            "Project" => "https://wotex.io",
            "W3C Web of Things" => "https://www.w3.org/WoT/"
          },
          files: ~w(.formatter.exs CHANGELOG.md LICENSE NOTICE README.md lib mix.exs)
        ]
      end

      defp docs do
        [
          main: "readme",
          extras: [
            {"README.md", title: "Overview"},
            {docs_path("plans/#{name}-completion.md"), title: "Completion Contract"},
            {"CHANGELOG.md", title: "Changelog"},
            {"LICENSE", title: "License"}
          ],
          groups_for_extras: [
            "Completion plans": ~r/docs\\/packages\\/#{name}\\/plans/,
            "Normative specifications": ~r/docs\\/packages\\/#{name}\\/specs/,
            Reference: ~r/CHANGELOG|LICENSE/
          ],
          source_ref: "#{name}-v" <> @version,
          source_url: @source_url,
          source_url_pattern:
            @source_url <> "/blob/#{name}-v" <> @version <> "/packages/#{name}/%{path}#L%{line}",
          formatters: ["html"]
        ]
      end

      defp docs_path(relative),
        do: Path.expand("../../docs/packages/#{name}/" <> relative, __DIR__)

      defp dialyzer do
        [
          plt_add_apps: [:mix, :ex_unit],
          flags: [:error_handling, :missing_return, :underspecs, :extra_return]
        ]
      end
    end
    """
  end

  defp claude_md(name, namespace) do
    """
    # #{namespace} Repository Contract

    This normal Mix library is `packages/#{name}` of the WoTEx family. The root
    `CLAUDE.md` governs the repository; this file governs work inside the
    package. State here what the package owns and what stays with the consumer.

    - Keep source, tests, docs, fixtures, metadata and history consumer-neutral.
      Say `consumer` or `consumer host`; never name a consumer or its local paths.
    - No database, Repo, migration, Phoenix, Ecto, global registry, application
      callback, framework integration or automatic network activity.
    - Loading the dependency starts no process and performs no runtime filesystem
      access. Long-lived work is returned to the consumer as child specifications.
    - Pure values never consult application environment, clocks or random sources.
    - Use W3C Web of Things terms exactly. Thing Description 1.1 is the baseline.
    - Public functions have documentation and types. One module per `.ex` file.
      Test modules use `@moduledoc false` followed by a blank line.
    - A sibling package is used only through its public, documented API.
    - `WOTEX_PATH_DEPS=1` is the sole local dependency switch and is
      development-only. Normal package identity uses released WoTEx dependencies.

    Run `WOTEX_PATH_DEPS=1 mix check --no-retry` before every local commit.
    Specifications live in `docs/packages/#{name}/specs/` and their status in
    that directory's `catalogue.yaml`; the completion contract lives in
    `docs/packages/#{name}/plans/`.

    ## Release metadata

    `CHANGELOG.md` is reserved for release tooling; never edit it directly. Only
    the human maintainer prepares or publishes a release.

    ## Git authority

    Never configure, add, change or remove a Git remote; push; create a tag;
    publish a package or release; or create equivalent remote state. Local
    commits use the identity already configured by the contributor; never record
    an agent, tool or bot as author, committer or co-author.
    """
  end

  defp readme(name, app, namespace) do
    """
    # #{namespace}

    **Describe what `#{name}` owns in one sentence.**

    `#{app}` is a package of the WoTEx family. It is a development checkout
    with an unstable public API; nothing is published on Hex yet.

    ## Installation

    ```elixir
    def deps do
      [{:#{app}, "~> 0.1.0"}]
    end
    ```

    ## Development

    ```sh
    cd packages/#{name}
    WOTEX_PATH_DEPS=1 mix deps.get
    WOTEX_PATH_DEPS=1 mix check --no-retry
    ```

    Specifications: [docs/packages/#{name}/specs](../../docs/packages/#{name}/specs).
    """
  end

  defp changelog(name) do
    """
    # Changelog

    All notable changes to `#{name}` are recorded here by the release tooling.

    ## Unreleased
    """
  end

  defp notice(name) do
    """
    WoTEx #{name}
    Copyright 2026 Wotex contributors

    This package is part of the WoTEx package family and is licensed under the
    Apache License, Version 2.0 (see LICENSE). Third-party attributions that
    apply to this package are listed below.
    """
  end

  defp library_module(name, namespace) do
    """
    defmodule #{namespace} do
      @moduledoc \"\"\"
      Entry point of `#{name}`.
      \"\"\"

      @doc "The package version."
      @spec version() :: String.t()
      def version, do: Mix.Project.config()[:version]
    end
    """
  end

  defp test_module(namespace) do
    """
    defmodule #{namespace}Test do
      @moduledoc false

      use ExUnit.Case, async: true

      test "reports a version" do
        assert is_binary(#{namespace}.version())
      end
    end
    """
  end

  defp check_archive(app, namespace) do
    """
    defmodule #{namespace}.Check.Archive do
      @moduledoc false

      # Builds the Hex archive without sibling path dependencies and verifies
      # that it ships code and governance files only.

      @required ~w(mix.exs LICENSE NOTICE README.md CHANGELOG.md)
      @forbidden ~w(docs test bin .check.exs .credo.exs CLAUDE.md)

      @spec main() :: :ok
      def main do
        version = Mix.Project.config()[:version]
        temporary = Path.join(System.tmp_dir!(), "#{app}-archive-" <> Integer.to_string(System.unique_integer([:positive])))
        File.mkdir_p!(temporary)
        archive = Path.join(temporary, "#{app}-" <> version <> ".tar")

        {output, status} =
          System.cmd("mix", ["hex.build", "--output", archive],
            env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}],
            stderr_to_stdout: true
          )

        IO.write(output)
        if status != 0, do: fail("mix hex.build exited with " <> Integer.to_string(status))

        :ok = :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(temporary))
        contents = Path.join(temporary, "contents.tar.gz")
        {:ok, entries} = :erl_tar.table(String.to_charlist(contents), [:compressed])
        files = Enum.map(entries, &to_string/1)
        File.rm_rf!(temporary)

        missing = Enum.reject(@required, &(&1 in files))

        shipped =
          Enum.filter(files, fn file ->
            Enum.any?(@forbidden, &(file == &1 or String.starts_with?(file, &1 <> "/")))
          end)

        if missing != [], do: fail("archive lacks " <> Enum.join(missing, ", "))
        if shipped != [], do: fail("archive ships " <> Enum.join(shipped, ", "))
        IO.puts("archive check passed")
        :ok
      end

      defp fail(message) do
        IO.puts(:stderr, "archive check failed: " <> message)
        System.halt(1)
      end
    end

    #{namespace}.Check.Archive.main()
    """
  end

  defp check_application_free(app, namespace) do
    """
    defmodule #{namespace}.Check.ApplicationFree do
      @moduledoc false

      # The package declares no application callback and starts no process.

      @spec main() :: :ok
      def main do
        unless Application.spec(:#{app}, :mod) in [nil, [], :undefined] do
          IO.puts(:stderr, "#{app} declares an application callback")
          System.halt(1)
        end

        {:ok, _started} = Application.ensure_all_started(:#{app})
        IO.puts("application-free check passed")
        :ok
      end
    end

    #{namespace}.Check.ApplicationFree.main()
    """
  end

  defp catalogue(name, app) do
    """
    schema_version: "1.2.0"
    package: "#{app}"
    completion_plan: "docs/plans/#{name}-completion.md"
    specifications: []
    """
  end

  defp plan(name) do
    """
    # #{name} completion contract

    Version 1.0.0. This plan is a versioned contract: a changed obligation
    needs a new plan version. Execution status stays in `docs/tasks/local/`.

    ## Obligations

    1. State what the package owns and the standards it claims, pinning the
       exact revision and executable evidence for every claim.
    2. Add each specification under `specs/` and record its
       `implementation_status` in `specs/catalogue.yaml`.

    ## Evidence

    `WOTEX_PATH_DEPS=1 mix check --no-retry` in `packages/#{name}`.
    """
  end
end
