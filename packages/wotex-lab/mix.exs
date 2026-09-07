defmodule WotexLab.MixProject do
  use Mix.Project

  @version "0.1.0"

  # Cowboy/Gun HTTP, cookie, link-header and HPACK/QPACK advisories reached only
  # through the WebSocket and QUIC transports of the optional `emqtt` dependency.
  # The Lab MQTT adapter selects `emqtt_sock` (plain TCP) and never `emqtt_ws` or
  # `emqtt_quic`, and no patched cowlib or gun release existed on 2026-09-08.
  # See docs/provenance/standards-and-dependencies.md; renew when one ships.
  @acknowledged_advisories [
    "GHSA-w4f7-4cxr-rv3c",
    "EEF-CVE-2026-43966",
    "EEF-CVE-2026-43969",
    "EEF-CVE-2026-43971"
  ]
  @source_url "https://github.com/wotex-project/wotex-lab"

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
      dialyzer: [plt_file: {:no_warn, "priv/plts/dialyxir.plt"}]
    ]
  end

  def application, do: [extra_applications: [:logger]]

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
      {:telemetry, "~> 1.3"},
      {:exqlite, "~> 0.40", optional: true},
      {:req, "~> 0.7.4", optional: true},
      {:ex_maude, "~> 0.4.1", optional: true},
      {:bandit, "~> 1.12", only: :test},
      {:plug, "~> 1.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test, :docs], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:yaml_elixir, "~> 2.12", only: [:dev, :test], runtime: false}
    ] ++ emqtt_dependencies()
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

      _value ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp package do
    [
      name: "wotex_lab",
      licenses: ["Apache-2.0"],
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      links: %{"GitHub" => @source_url, "Project" => "https://wotex.io"},
      files: ~w(lib priv/fixtures priv/models docs/specs docs/plans docs/decisions docs/provenance
        .formatter.exs mix.exs README.md LICENSE NOTICE CHANGELOG.md SECURITY.md CONTRIBUTING.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        [
          "README.md",
          "SECURITY.md",
          "CONTRIBUTING.md",
          {"LICENSE", [title: "License"]},
          {"NOTICE", [title: "Notices"]}
        ] ++
          Path.wildcard("docs/{specs,plans,decisions,provenance}/*.md"),
      groups_for_extras: [
        Specifications: ~r/docs\/specs/,
        "Completion contract": ~r/docs\/plans/,
        Decisions: ~r/docs\/decisions/,
        Provenance: ~r/docs\/provenance/
      ],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
