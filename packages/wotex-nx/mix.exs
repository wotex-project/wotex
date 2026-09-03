defmodule WotexNx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex-nx"

  def project do
    [
      app: :wotex_nx,
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
      name: "Wotex Nx"
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
      {:nx, "~> 0.13.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :docs], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:doctest_formatter, "~> 0.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.3", only: :test}
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
      setup: ["deps.get", "deps.compile"],
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp description do
    "Typed, deterministic conversion between W3C Web of Things observations and Elixir Nx"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      name: "wotex_nx",
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/wotex_nx",
        "Project" => "https://wotex.io",
        "W3C Web of Things" => "https://www.w3.org/WoT/",
        "Nx" => "https://github.com/elixir-nx/nx"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files: ~w[
        lib
        docs
        .formatter.exs
        mix.exs
        README.md
        LICENSE
        NOTICE
        CHANGELOG.md
        SECURITY.md
        CONTRIBUTING.md
      ]
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
      ],
      groups_for_modules: [
        "Public API": [Wotex.Nx, Wotex.Nx.Encoder, Wotex.Nx.Decoder],
        "Input contracts": [
          Wotex.Nx.Feature,
          Wotex.Nx.Observation,
          Wotex.Nx.Row,
          Wotex.Nx.Schema,
          Wotex.Nx.Window
        ],
        "Output contracts": [
          Wotex.Nx.ActionProposal,
          Wotex.Nx.Anomaly,
          Wotex.Nx.Encoded,
          Wotex.Nx.OutputSchema,
          Wotex.Nx.Prediction
        ],
        "Extension ports": [Wotex.Nx.UnitConverter]
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
