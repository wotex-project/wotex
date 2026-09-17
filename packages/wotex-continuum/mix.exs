defmodule WotexContinuum.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"
  @docs_root Path.expand("../../docs/packages/wotex-continuum", __DIR__)

  def project do
    [
      app: :wotex_continuum,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      name: "Wotex Continuum"
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.lcov": :test,
        check: :test
      ]
    ]
  end

  defp deps do
    [
      wotex_dependency(),
      {:jason, "~> 1.4.5"},
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

  defp wotex_dependency do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {:wotex, "~> 0.1"}

      "1" ->
        {:wotex, path: Path.expand("../wotex", __DIR__), override: true}

      _value ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
    end
  end

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp description do
    "Immutable continuum exchange contracts for Elixir and W3C Web of Things systems"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      name: "wotex_continuum",
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-continuum/CHANGELOG.md",
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-continuum",
        "Documentation" => "https://hexdocs.pm/wotex_continuum",
        "Project" => "https://wotex.io",
        "W3C Web of Things" => "https://www.w3.org/WoT/"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files:
        ~w(lib priv/schemas test/vectors .formatter.exs mix.exs README.md LICENSE NOTICE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        Path.join(@docs_root, "plans/wotex-continuum-completion.md"),
        Path.join(@docs_root, "specs/WCT-C01-contract-map.md"),
        Path.join(@docs_root, "specs/WCT-C02-admission-map.md"),
        Path.join(@docs_root, "specs/WCT-C03-schema-agreement.md"),
        Path.join(@docs_root, "specs/WCT-C04-archive-consumer.md"),
        Path.join(@docs_root, "specs/WCT-C05-release-dossier.md"),
        Path.join(@docs_root, "specs/WCT.01-manifest-context-capability.md"),
        Path.join(@docs_root, "specs/WCT.02-exchange-values.md"),
        Path.join(@docs_root, "specs/WCT.03-mode-lifecycle-exit.md"),
        Path.join(@docs_root, "THREAT_MODEL.md"),
        "SECURITY.md",
        "GOVERNANCE.md"
      ],
      groups_for_extras: [
        "Completion plans": ~r/docs\/packages\/wotex-continuum\/plans/,
        "Verification maps": ~r/docs\/packages\/wotex-continuum\/specs\/WCT-C/,
        Specifications: ~r/docs\/packages\/wotex-continuum\/specs\/WCT\./,
        Security: ~r/docs\/packages\/wotex-continuum\/THREAT_MODEL/,
        Project: ~r/(SECURITY|GOVERNANCE)\.md/
      ],
      groups_for_modules: [
        "Public API": [
          WotexContinuum,
          WotexContinuum.Codec,
          WotexContinuum.CanonicalJSON,
          WotexContinuum.Error,
          WotexContinuum.Schema,
          WotexContinuum.Value
        ],
        "Continuum context": [
          WotexContinuum.Capability,
          WotexContinuum.CapabilityRequirement,
          WotexContinuum.ExecutionScope,
          WotexContinuum.Manifest,
          WotexContinuum.Mode
        ],
        "Exchange values": [
          WotexContinuum.ActionIntent,
          WotexContinuum.ActionResult,
          WotexContinuum.Delivery,
          WotexContinuum.EvidenceReference,
          WotexContinuum.ObservationProposal
        ],
        "Lifecycle and portability": [
          WotexContinuum.Artifact,
          WotexContinuum.Compatibility,
          WotexContinuum.Degradation,
          WotexContinuum.ExitReceipt,
          WotexContinuum.Failure,
          WotexContinuum.Lifecycle,
          WotexContinuum.Limits,
          WotexContinuum.ThingReference
        ]
      ],
      source_ref: "wotex-continuum-v#{@version}",
      source_url: @source_url,
      source_url_pattern:
        "#{@source_url}/blob/wotex-continuum-v#{@version}/packages/wotex-continuum/%{path}#L%{line}",
      formatters: ["html"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
