defmodule Wotex.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/wotex-project/wotex"

  def project do
    [
      app: :wotex,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Storage-neutral W3C Web of Things values and Thing Description mechanics",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_coverage: [summary: [threshold: 90]]
    ]
  end

  def application do
    [extra_applications: []]
  end

  def cli do
    [preferred_envs: [check: :test]]
  end

  defp deps do
    [
      {:ex_json_schema, "~> 0.11"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --cover --warnings-as-errors",
        "docs --warnings-as-errors",
        "cmd bin/check-boundary",
        "cmd env MIX_ENV=dev mix hex.build"
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => @source_url,
        "Project" => "https://wotex.io",
        "W3C Web of Things" => "https://www.w3.org/WoT/"
      },
      maintainers: ["Wotex contributors"],
      files:
        ~w(.formatter.exs CHANGELOG.md CODE_OF_CONDUCT.md CONTRIBUTING.md GOVERNANCE.md LICENSE NOTICE README.md SECURITY.md docs lib mix.exs priv)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/specs/WTX.01-thing-description.md",
        "docs/specs/WTX.02-affordance-values.md",
        "docs/specs/WTX.03-errors-extensions-and-compatibility.md",
        "docs/provenance/w3c-td-schema-1.1.md"
      ],
      groups_for_extras: [
        "Normative specifications": ~r/docs\/specs/,
        Provenance: ~r/docs\/provenance/
      ]
    ]
  end
end
