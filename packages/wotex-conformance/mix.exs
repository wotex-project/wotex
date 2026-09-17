defmodule WotexConformance.MixProject do
  use Mix.Project

  @source_url "https://github.com/wotex-project/wotex"
  @version "0.1.0"
  @docs_root Path.expand("../../docs/packages/wotex-conformance", __DIR__)

  def project do
    [
      app: :wotex_conformance,
      name: "Wotex Conformance",
      version: @version,
      elixir: "~> 1.18",
      start_permanent: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [~r|test/fixtures/|],
      deps: deps(),
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
    [extra_applications: [:crypto]]
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.10", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :docs], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"],
      package: "cmd env MIX_ENV=dev mix hex.build"
    ]
  end

  defp description do
    "Subject-independent W3C Web of Things claims, vectors, execution, and evidence reports"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-conformance/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/wotex_conformance",
        "Project" => "https://wotex.io",
        "Source" => @source_url,
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-conformance"
      },
      files: [
        "lib",
        "priv/schemas",
        "priv/vectors",
        ".formatter.exs",
        "CHANGELOG.md",
        "LICENSE",
        "NOTICE",
        "README.md",
        "mix.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        {"README.md", title: "Overview"},
        {doc("plans/wotex-conformance-completion.md"), title: "Completion Contract"},
        {Path.expand("../../docs/packages/wotex-conformance/security.md", __DIR__),
         title: "Security"},
        {doc("specs/WCF.01-conformance-runner.md"), title: "Conformance runner"},
        {doc("decisions/0001-external-target-isolation.md"), title: "External target isolation"},
        {doc("decisions/0002-evidence-digests.md"), title: "Evidence digests"},
        {doc("decisions/0003-normalized-observations.md"), title: "Normalized observations"},
        {doc("decisions/0004-discovery-corpus-boundary.md"), title: "Discovery corpus boundary"},
        {doc("provenance/source.md"), title: "Source provenance"},
        {doc("provenance/standards.md"), title: "Standards provenance"},
        {doc("provenance/assertion-inventory.md"), title: "Assertion inventory"},
        {doc("provenance/archive-consumer.md"), title: "Archive-only consumer"},
        {doc("provenance/external-lifecycle.md"), title: "External target lifecycle"},
        {doc("provenance/package-inputs.md"), title: "Package inputs"},
        {doc("provenance/runtime-compatibility.md"), title: "Runtime compatibility"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE", title: "License"}
      ],
      groups_for_extras: [
        "Completion plans": ~r|docs/packages/wotex-conformance/plans/|,
        Specifications: ~r|docs/packages/wotex-conformance/specs/|,
        Decisions: ~r|docs/packages/wotex-conformance/decisions/|,
        Provenance: ~r|docs/packages/wotex-conformance/provenance/|,
        Reference: ~r/CHANGELOG|security|CONTRIBUTING|GOVERNANCE|LICENSE/
      ],
      groups_for_modules: [
        Contracts: [
          Wotex.Conformance.Claim,
          Wotex.Conformance.Observation,
          Wotex.Conformance.Expectation,
          Wotex.Conformance.Subject,
          Wotex.Conformance.Vector,
          Wotex.Conformance.Result,
          Wotex.Conformance.Report,
          Wotex.Conformance.Target.Response,
          Wotex.Conformance.Value
        ],
        Execution: [
          Wotex.Conformance.Corpus,
          Wotex.Conformance.Runner,
          Wotex.Conformance.Target,
          Wotex.Conformance.Target.External
        ],
        Integrity: [
          Wotex.Conformance.Artifact,
          Wotex.Conformance.Canonical,
          Wotex.Conformance.Error,
          Wotex.Conformance.Pointer
        ]
      ],
      source_ref: "wotex-conformance-v#{@version}",
      source_url: @source_url,
      source_url_pattern:
        "#{@source_url}/blob/wotex-conformance-v#{@version}/packages/wotex-conformance/%{path}#L%{line}",
      formatters: ["html", "markdown", "epub"]
    ]
  end

  defp doc(path), do: Path.join(@docs_root, path)

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
