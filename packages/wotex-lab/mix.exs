defmodule WotexLab.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex-lab"

  def project do
    [
      app: :wotex_lab,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      name: "Wotex Lab",
      description: "An independent WoT consumer laboratory for Elixir, OTP and Nx",
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_file: {:no_warn, "priv/plts/dialyxir.plt"}]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  def cli do
    [preferred_envs: [check: :test, coveralls: :test, "test.cover": :test]]
  end

  defp deps do
    [
      wotex_dependency(:wotex, "wotex"),
      wotex_dependency(:wotex_nx, "wotex-nx"),
      wotex_dependency(:wotex_runtime, "wotex-runtime"),
      wotex_dependency(:wotex_directory, "wotex-directory"),
      {:nx, "~> 0.13.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test, :docs], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp wotex_dependency(app, directory) do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {app, "~> 0.1.0"}

      "1" ->
        if Mix.env() in [:dev, :test, :docs] do
          {app, path: Path.expand("../#{directory}", __DIR__), env: :dev, override: true}
        else
          raise "WOTEX_PATH_DEPS is allowed only in development, test or docs"
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

  defp package do
    [
      name: "wotex_lab",
      licenses: ["Apache-2.0"],
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      links: %{"GitHub" => @source_url, "Project" => "https://wotex.io"},
      files: ~w(lib priv/fixtures docs/specs docs/plans docs/decisions docs/provenance
        .formatter.exs mix.exs README.md LICENSE NOTICE CHANGELOG.md SECURITY.md CONTRIBUTING.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        [
          "README.md",
          "SECURITY.md",
          "CONTRIBUTING.md",
          {"LICENSE", [title: "License"]},
          {"NOTICE", [title: "Notices"]}
        ] ++
          Path.wildcard("docs/{specs,plans,decisions,provenance}/*.md"),
      groups_for_extras: [
        Specifications: ~r/docs\/specs/,
        "Completion contract": ~r/docs\/plans/,
        Decisions: ~r/docs\/decisions/,
        Provenance: ~r/docs\/provenance/
      ],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
