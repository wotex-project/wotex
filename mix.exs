defmodule Wotex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"

  def project do
    [
      app: :wotex,
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
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer(),
      name: "Wotex"
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
        "coveralls.lcov": :test
      ]
    ]
  end

  defp deps do
    [
      {:ex_json_schema, "~> 0.11"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
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

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"]
    ]
  end

  defp description do
    "Storage-neutral W3C Web of Things 1.1 values, validation, and " <>
      "deterministic Thing Description encoding for Elixir"
  end

  defp package do
    [
      name: "wotex",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/wotex",
        "Project" => "https://wotex.io",
        "W3C Web of Things" => "https://www.w3.org/WoT/"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files:
        ~w(.formatter.exs CHANGELOG.md CODE_OF_CONDUCT.md CONTRIBUTING.md GOVERNANCE.md LICENSE NOTICE README.md SECURITY.md docs/plans docs/provenance docs/specs lib mix.exs priv/w3c)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "docs/plans/wotex-completion.md": [title: "Completion Contract"],
        "docs/specs/WTX.01-thing-description.md": [title: "Thing Description"],
        "docs/specs/WTX.02-affordance-values.md": [title: "Affordance Values"],
        "docs/specs/WTX.03-errors-extensions-and-compatibility.md": [
          title: "Errors, Extensions, and Compatibility"
        ],
        "docs/specs/WTX.04-thing-model.md": [title: "Thing Model"],
        "docs/provenance/w3c-td-schema-1.1.md": [title: "TD 1.1 Schema Provenance"],
        "docs/provenance/w3c-tm-schema-1.1.md": [title: "Thing Model Schema Provenance"],
        "CHANGELOG.md": [title: "Changelog"],
        "SECURITY.md": [title: "Security"],
        "CONTRIBUTING.md": [title: "Contributing"],
        NOTICE: [title: "Third-party Notices"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Completion plans": ~r/docs\/plans/,
        "Normative specifications": ~r/docs\/specs/,
        Provenance: ~r/docs\/provenance/,
        Reference: ~r/CHANGELOG|SECURITY|CONTRIBUTING|NOTICE|LICENSE/
      ],
      groups_for_modules: [
        "Thing Description and Models": [
          Wotex,
          Wotex.ThingDescription,
          Wotex.ThingModel,
          Wotex.Error
        ],
        "Interaction Affordances": [
          Wotex.PropertyAffordance,
          Wotex.ActionAffordance,
          Wotex.EventAffordance
        ],
        "TD Values": [Wotex.DataSchema, Wotex.Form, Wotex.SecurityScheme],
        "JSON admission": [Wotex.JSON, Wotex.JSON.Limits]
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html"]
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
