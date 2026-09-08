defmodule WotexRuntime.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex-runtime"

  def project do
    [
      app: :wotex_runtime,
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
      name: "Wotex Runtime"
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
      wotex_dep(),
      {:telemetry, "~> 1.3"},
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

  defp wotex_dep do
    case System.get_env("WOTEX_PATH_DEPS") do
      "1" -> {:wotex, path: "../wotex"}
      _ -> {:wotex, "~> 0.1.0"}
    end
  end

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"]
    ]
  end

  defp description do
    "Caller-owned ConsumedThing and ExposedThing interaction mechanics " <>
      "with explicit transport and credential ports"
  end

  defp package do
    [
      name: "wotex_runtime",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/wotex_runtime",
        "Project" => "https://wotex.io",
        "W3C Web of Things" => "https://www.w3.org/WoT/"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files:
        ~w(.formatter.exs CHANGELOG.md CODE_OF_CONDUCT.md CONTRIBUTING.md GOVERNANCE.md LICENSE NOTICE README.md SECURITY.md docs/plans docs/specs lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "docs/plans/wotex-runtime-completion.md": [title: "Completion Contract"],
        "docs/specs/WRT.01-consumed-thing-runtime.md": [title: "ConsumedThing Runtime"],
        "docs/specs/WRT.02-exposed-thing-runtime.md": [title: "ExposedThing Runtime"],
        "docs/specs/WRT.03-thing-level-interactions.md": [
          title: "Thing-level Interactions"
        ],
        "CHANGELOG.md": [title: "Changelog"],
        "SECURITY.md": [title: "Security"],
        "CONTRIBUTING.md": [title: "Contributing"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Completion plans": ~r/docs\/plans/,
        "Normative specifications": ~r/docs\/specs/,
        Reference: ~r/CHANGELOG|SECURITY|CONTRIBUTING|LICENSE/
      ],
      groups_for_modules: [
        "Runtime API": [Wotex.Runtime, Wotex.Runtime.ConsumedThing, Wotex.Runtime.ExposedThing],
        "Interaction Planning": [
          Wotex.Runtime.BindingProfile,
          Wotex.Runtime.FormSelector,
          Wotex.Runtime.Selection,
          Wotex.Runtime.Request,
          Wotex.Runtime.Result,
          Wotex.Runtime.Context,
          Wotex.Runtime.Limits,
          Wotex.Runtime.Retry,
          Wotex.Runtime.Error
        ],
        "Consumer Ports": [Wotex.Runtime.Credentials, Wotex.Runtime.Transport],
        Subscriptions: [Wotex.Runtime.Subscription],
        Observability: [Wotex.Runtime.Telemetry]
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
