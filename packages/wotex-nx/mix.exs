defmodule WotexNx.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/wotex-project/wotex-nx"

  def project do
    [
      app: :wotex_nx,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: "Typed W3C Web of Things observation and Nx conversion boundary",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_coverage: [
        summary: [threshold: 90],
        ignore_modules: [Wotex.Nx.TestFactory, Wotex.Nx.TestUnitConverter]
      ]
    ]
  end

  def application, do: [extra_applications: []]

  def cli, do: [preferred_envs: [check: :test]]

  defp deps do
    [
      wotex_dependency(),
      {:nx, "~> 0.13.1"},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :docs], runtime: false}
    ]
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --cover --warnings-as-errors",
        "docs --warnings-as-errors",
        "cmd bin/check-boundary",
        "package"
      ],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => @source_url,
        "Project" => "https://wotex.io",
        "W3C Web of Things" => "https://www.w3.org/WoT/",
        "Nx" => "https://github.com/elixir-nx/nx"
      },
      maintainers: ["Wotex contributors"],
      files:
        ~w(.claude .formatter.exs AGENTS.md CHANGELOG.md CLAUDE.md CODE_OF_CONDUCT.md CONTRIBUTING.md GOVERNANCE.md LICENSE NOTICE README.md SECURITY.md docs lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/specs/WNX.01-observation-numerical-boundary.md",
        "docs/decisions/0001-caller-owned-execution.md",
        "docs/decisions/0002-batch-and-output-contract.md",
        "docs/provenance/standards-and-dependencies.md",
        "SECURITY.md"
      ],
      groups_for_extras: [
        Specifications: ~r/docs\/specs/,
        Decisions: ~r/docs\/decisions/,
        Provenance: ~r/docs\/provenance/,
        Project: ~r/SECURITY\.md/
      ]
    ]
  end
end
