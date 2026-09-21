defmodule WotexLab.MixProject do
  use Mix.Project

  @version "0.1.0"

  # Dated, scoped acknowledgements are justified in
  # docs/packages/wotex-lab/provenance/standards-and-dependencies.md and protected by regression
  # tests where the affected code is reachable. Renew them whenever the lock or
  # advisory records change.
  @acknowledged_advisories [
    "GHSA-w4f7-4cxr-rv3c",
    "EEF-CVE-2026-43966",
    "EEF-CVE-2026-43969",
    "EEF-CVE-2026-43971"
  ]
  @source_url "https://github.com/wotex-project/wotex"
  @docs "../../docs/packages/wotex-lab"

  @spec project() :: keyword()
  def project do
    [
      app: :wotex_lab,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      name: "Wotex Lab",
      description: "An independent WoT consumer laboratory for Elixir, OTP and Nx",
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      hex: [ignore_advisories: @acknowledged_advisories],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyxir.plt"},
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  @spec application() :: keyword()
  def application, do: [extra_applications: [:logger]]

  @spec cli() :: keyword()
  def cli do
    [preferred_envs: [check: :test, coveralls: :test, "test.cover": :test]]
  end

  defp deps do
    [
      wotex_dependency(:wotex, "wotex"),
      wotex_dependency(:wotex_nx, "wotex-nx"),
      wotex_dependency(:wotex_runtime, "wotex-runtime", optional: true),
      wotex_dependency(:wotex_directory, "wotex-directory", optional: true),
      wotex_dependency(:wotex_binding_http, "wotex-binding-http", optional: true),
      wotex_dependency(:wotex_binding_mqtt, "wotex-binding-mqtt", optional: true),
      wotex_dependency(:wotex_conformance, "wotex-conformance", only: [:dev, :test]),
      wotex_dependency(:wotex_continuum, "wotex-continuum", optional: true),
      {:nx, "~> 0.13.1"},
      {:explorer, "~> 0.12.0", optional: true},
      {:axon, "~> 0.8.1", optional: true},
      {:exla, "~> 0.13.1", optional: true},
      {:telemetry, "~> 1.3"},
      {:exqlite, "~> 0.40", optional: true},
      {:req, "~> 0.7.4", optional: true},
      {:ex_maude, "~> 0.4.1", optional: true},
      {:bandit, "~> 1.12", only: :test},
      {:plug, "~> 1.18", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.5", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3.4", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      doc_shell_dependency(),
      {:ex_doc, "~> 0.40", only: [:dev, :test, :docs], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:yaml_elixir, "~> 2.12", only: [:dev, :test, :docs], runtime: false}
    ] ++ emqtt_dependencies()
  end

  defp doc_shell_dependency do
    case {System.get_env("WOTEX_PATH_DEPS"), System.get_env("DOC_SHELL_CANDIDATE")} do
      {"1", path} when is_binary(path) and path != "" ->
        if Mix.env() in [:dev, :test, :docs] do
          {:doc_shell,
           path: Path.expand(path),
           env: :prod,
           only: [:dev, :test, :docs],
           runtime: false,
           override: true}
        else
          raise "DOC_SHELL_CANDIDATE is allowed only in development, test or docs"
        end

      {_, nil} ->
        {:doc_shell, "== 0.4.0", only: [:dev, :test, :docs], runtime: false}

      {_, ""} ->
        {:doc_shell, "== 0.4.0", only: [:dev, :test, :docs], runtime: false}

      _ ->
        raise "DOC_SHELL_CANDIDATE requires WOTEX_PATH_DEPS=1"
    end
  end

  # emqtt lists quicer as a hard dependency although its application file does
  # not start it. Outside production the Lab compiles emqtt without its QUIC
  # transport and fetches quicer only to satisfy the resolver, never building
  # it, so no msquic download or cmake run enters the Lab setup. Hex package
  # metadata cannot carry `:system_env` or `override: true`, so production
  # declares the plain optional requirement and a host that selects `emqtt`
  # sets `BUILD_WITHOUT_QUIC=1` in its own build. The adapter uses TCP only.
  defp emqtt_dependencies do
    if Mix.env() == :prod do
      [{:emqtt, "~> 1.15", optional: true}]
    else
      [
        {:emqtt, "~> 1.15", optional: true, system_env: [{"BUILD_WITHOUT_QUIC", "1"}]},
        {:quicer, "0.2.15", optional: true, compile: false, app: false, override: true}
      ]
    end
  end

  # The base package needs core, Wotex Nx, Nx and telemetry for the first
  # tensor. Runtime, bindings, Directory and Continuum are optional profile
  # packages a host selects; the conformance runner is a development and test
  # dependency because the Lab target answers with the core package alone.
  defp wotex_dependency(app, directory, opts \\ []) do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {app, "~> 0.1.0", opts}

      "1" ->
        if Mix.env() in [:dev, :test, :docs] do
          {app, [path: Path.expand("../#{directory}", __DIR__), env: :dev, override: true] ++ opts}
        else
          raise "WOTEX_PATH_DEPS is allowed only in development, test or docs"
        end

      _ ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=prod mix hex.build"
    ]
  end

  defp package do
    [
      name: "wotex_lab",
      licenses: ["Apache-2.0"],
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-lab/CHANGELOG.md",
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-lab"
      },
      # Tarballs ship consumer usage rules but no specification Markdown;
      # specifications reach consumers through HexDocs.
      exclude_patterns: [~r{\Apriv/conformance/native/target(?:/|\z)}],
      files: ~w(lib priv/fixtures priv/models priv/cookbooks priv/conformance priv/provenance
        .formatter.exs mix.exs README.md usage-rules.md LICENSE NOTICE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        [
          "README.md",
          "../../docs/packages/wotex-lab/security.md",
          {"CHANGELOG.md", [title: "Changelog"]},
          {"LICENSE", [title: "License"]},
          {"NOTICE", [title: "Notices"]}
        ] ++
          Path.wildcard("#{@docs}/{specs,plans,decisions,provenance}/*.md") ++
          Path.wildcard("bench/output/*.md"),
      groups_for_extras: [
        Specifications: ~r/wotex-lab\/specs/,
        "Completion contract": ~r/wotex-lab\/plans/,
        Decisions: ~r/wotex-lab\/decisions/,
        Provenance: ~r/wotex-lab\/provenance/,
        Benchmarks: ~r/bench\/output/
      ],
      source_ref: "wotex-lab-v#{@version}",
      source_url: @source_url,
      source_url_pattern: &source_url/2
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

    "#{@source_url}/blob/wotex-lab-v#{@version}/#{repository_path}#L#{line}"
  end
end
