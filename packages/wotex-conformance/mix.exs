defmodule WotexConformance.MixProject do
  use Mix.Project

  @source_url "https://github.com/wotex-project/wotex-conformance"
  @version "0.1.0-dev"

  def project do
    [
      app: :wotex_conformance,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [~r|test/fixtures/|],
      deps: deps(),
      description: "Subject-independent conformance claims, vectors, runners, and reports",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Project" => "https://wotex.io",
        "Source" => @source_url,
        "Specifications" => "#{@source_url}/tree/main/docs/specs"
      },
      files: [
        "lib",
        "priv",
        "docs",
        ".formatter.exs",
        "CHANGELOG.md",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "GOVERNANCE.md",
        "LICENSE",
        "NOTICE",
        "README.md",
        "SECURITY.md",
        "mix.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "GOVERNANCE.md",
        "docs/specs/WCF.01-conformance-runner.md",
        "docs/decisions/0001-external-target-isolation.md",
        "docs/decisions/0002-evidence-digests.md"
      ],
      groups_for_modules: [
        Contracts: [
          Wotex.Conformance.Claim,
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
          Wotex.Conformance.Error
        ]
      ]
    ]
  end
end
