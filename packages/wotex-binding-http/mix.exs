defmodule WotexBindingHTTP.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/wotex-project/wotex-binding-http"

  def project do
    [
      app: :wotex_binding_http,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Caller-owned HTTP and Server-Sent Events binding for Wotex Runtime",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_ignore_filters: [~r{^test/support/}],
      test_coverage: [summary: [threshnew: 90]]
    ]
  end

  def application, do: [extra_applications: []]

  def cli, do: [preferred_envs: [check: :test]]

  defp deps do
    [
      wotex_dep(),
      wotex_runtime_dep(),
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false}
    ]
  end

  defp wotex_dep do
    case System.get_env("WOTEX_PATH_DEPS") do
      "1" -> {:wotex, path: "../wotex", override: true}
      _ -> {:wotex, "~> 0.1.0"}
    end
  end

  defp wotex_runtime_dep do
    case System.get_env("WOTEX_PATH_DEPS") do
      "1" -> {:wotex_runtime, path: "../wotex-runtime"}
      _ -> {:wotex_runtime, "~> 0.1.0"}
    end
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --cover --warnings-as-errors",
        "docs",
        "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
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
        ~w(.formatter.exs CHANGELOG.md CODE_OF_CONDUCT.md CONTRIBUTING.md GOVERNANCE.md LICENSE NOTICE README.md SECURITY.md docs lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/standards-baseline.md",
        "docs/runtime-baseline.md",
        "docs/specs/WBH.01-http-transport.md",
        "docs/specs/WBH.02-client-port-and-values.md",
        "docs/specs/WBH.03-sse-subscriptions.md"
      ],
      groups_for_extras: [
        "Normative package specifications": ~r/docs\/specs/,
        "Standards baseline": ~r/docs\/standards-baseline/
      ]
    ]
  end
end
