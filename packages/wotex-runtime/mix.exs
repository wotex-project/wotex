defmodule WotexRuntime.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/wotex-project/wotex-runtime"

  def project do
    [
      app: :wotex_runtime,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Caller-owned ConsumedThing and ExposedThing runtime mechanics",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_ignore_filters: [~r{^test/support/}],
      test_coverage: [summary: [threshold: 90]]
    ]
  end

  def application, do: [extra_applications: []]

  def cli, do: [preferred_envs: [check: :test]]

  defp deps do
    [
      wotex_dep(),
      {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false}
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
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --cover --warnings-as-errors",
        "docs",
        "cmd bin/check-boundary",
        "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"Source" => @source_url, "Project" => "https://wotex.io"},
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
        "docs/specs/WRT.01-consumed-thing-runtime.md",
        "docs/specs/WRT.02-exposed-thing-runtime.md"
      ]
    ]
  end
end
