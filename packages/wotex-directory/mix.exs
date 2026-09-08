defmodule WotexDirectory.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex-directory"

  def project do
    [
      app: :wotex_directory,
      name: "Wotex Directory",
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      hex: [ignore_advisories: ["EEF-CVE-2026-32686"]],
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer()
    ]
  end

  def application do
    [extra_applications: []]
  end

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
      wotex_dependency(),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :docs], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp description do
    "Storage-neutral Thing Description Directory mechanics for W3C Web of Things consumers"
  end

  defp wotex_dependency do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {:wotex, "~> 0.1.0"}

      "1" ->
        if Mix.env() in [:dev, :test, :docs] do
          {:wotex, path: Path.expand("../wotex", __DIR__), override: true}
        else
          raise "WOTEX_PATH_DEPS is allowed only in non-production development environments"
        end

      _value ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
    end
  end

  defp package do
    [
      files: [
        ".claude",
        ".formatter.exs",
        "AGENTS.md",
        "CLAUDE.md",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "GOVERNANCE.md",
        "LICENSE",
        "NOTICE",
        "README.md",
        "CHANGELOG.md",
        "SECURITY.md",
        "docs/decisions",
        "docs/plans",
        "docs/provenance",
        "docs/specs",
        "lib",
        "mix.exs"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/wotex_directory",
        "Homepage" => "https://wotex.io",
        "Source" => @source_url
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "docs/plans/wotex-directory-completion.md": [title: "Completion Contract"],
        "docs/specs/WTD.01-directory-contract.md": [title: "Directory contract"],
        "docs/decisions/0001-consumer-owned-runtime.md": [title: "Consumer-owned runtime"],
        "docs/decisions/0002-listing-and-expiry.md": [title: "Listing and expiry"],
        "docs/provenance/w3c-sources.md": [title: "W3C sources"],
        "CHANGELOG.md": [title: "Changelog"],
        "SECURITY.md": [title: "Security"],
        "CONTRIBUTING.md": [title: "Contributing"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Completion plans": ~r|docs/plans/|,
        Specifications: ~r|docs/specs/|,
        Decisions: ~r|docs/decisions/|,
        Provenance: ~r|docs/provenance/|,
        Reference: ~r/CHANGELOG|SECURITY|CONTRIBUTING|LICENSE/
      ],
      groups_for_modules: [
        "Public API": [Wotex.Directory],
        "Configuration and ports": [
          Wotex.Directory.Authorization,
          Wotex.Directory.Clock,
          Wotex.Directory.Clock.System,
          Wotex.Directory.Identifier,
          Wotex.Directory.Repository,
          Wotex.Directory.Service
        ],
        "Directory values": [
          Wotex.Directory.Context,
          Wotex.Directory.Cursor,
          Wotex.Directory.Entry,
          Wotex.Directory.Error,
          Wotex.Directory.Event,
          Wotex.Directory.Expiry,
          Wotex.Directory.Introduction,
          Wotex.Directory.Mutation,
          Wotex.Directory.Page,
          Wotex.Directory.Query,
          Wotex.Directory.Registration
        ],
        Mechanics: [
          Wotex.Directory.MergePatch,
          Wotex.Directory.ThingDescriptions
        ]
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html", "markdown", "epub"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyxir.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
