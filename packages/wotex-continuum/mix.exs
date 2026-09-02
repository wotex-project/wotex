defmodule WotexContinuum.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/wotex-project/wotex-continuum"

  def project do
    [
      app: :wotex_continuum,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Host-neutral continuum exchange values for Elixir and W3C Web of Things systems",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_coverage: [summary: [threshold: 90]]
    ]
  end

  def cli do
    [preferred_envs: [quality: :test]]
  end

  def application do
    []
  end

  defp deps do
    [
      wotex_dependency(),
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp wotex_dependency do
    requirement = ">= 0.1.0-dev and < 0.2.0"

    case System.get_env("WOTEX_CORE_PATH") do
      nil -> {:wotex, requirement}
      path -> {:wotex, requirement, path: path}
    end
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => @source_url,
        "W3C Web of Things" => "https://www.w3.org/WoT/"
      },
      files:
        ~w(docs lib priv provenance specs test/vectors .formatter.exs mix.exs README.md LICENSE NOTICE CHANGELOG.md SECURITY.md GOVERNANCE.md CONTRIBUTING.md CODE_OF_CONDUCT.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "specs/WCT.01-manifest-context-capability.md",
        "specs/WCT.02-exchange-values.md",
        "specs/WCT.03-mode-lifecycle-exit.md",
        "docs/THREAT_MODEL.md",
        "SECURITY.md",
        "GOVERNANCE.md"
      ],
      groups_for_extras: [
        Specifications: ~r/specs\//,
        Security: ~r/docs\//,
        Project: ~r/(SECURITY|GOVERNANCE)\.md/
      ]
    ]
  end
end
