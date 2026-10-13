defmodule Wotex.Routines.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"
  @docs Path.expand("../../docs/packages/wotex-routines", __DIR__)

  def project do
    [
      app: :wotex_routines,
      name: "Wotex Routines",
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
      dialyzer: dialyzer()
    ]
  end

  def application, do: [extra_applications: [:crypto]]

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.lcov": :test,
        "test.cover": :test
      ]
    ]
  end

  defp deps do
    [
      sibling(:wotex, "wotex"),
      sibling(:wotex_continuum, "wotex-continuum"),
      {:ex_booking, "== 0.2.3", optional: true},
      {:ex_maude, "== 0.5.0", optional: true},
      {:benchee, "~> 1.5", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test, :docs], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  # WOTEX_PATH_DEPS=1 is the only sibling switch and is allowed in the dev,
  # test and docs environments: unset means the Hex requirement, 1 means
  # the sibling checkout under packages/, loaded in :dev so that its own
  # switch guard accepts it.
  defp sibling(app, directory) do
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

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp description do
    "Bounded inert routine semantics over installed Web of Things capabilities"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-routines/CHANGELOG.md",
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-routines"
      },
      files:
        ~w(lib priv .formatter.exs mix.exs README.md usage-rules.md CHANGELOG.md LICENSE NOTICE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        ["README.md", "CHANGELOG.md", "LICENSE", "NOTICE"] ++
          Path.wildcard("#{@docs}/{specs,plans,decisions,provenance}/*.md") ++
          Path.wildcard("bench/output/*.md"),
      groups_for_extras: [
        Specifications: ~r{docs/packages/wotex-routines/specs/},
        "Completion contract": ~r{docs/packages/wotex-routines/plans/},
        Decisions: ~r{docs/packages/wotex-routines/decisions/},
        Provenance: ~r{docs/packages/wotex-routines/provenance/},
        Benchmarks: ~r{bench/output/}
      ],
      source_ref: "wotex-routines-v#{@version}",
      source_url: @source_url,
      source_url_pattern: &source_url/2,
      formatters: ["html"]
    ]
  end

  # Links modules and the specification extras under the repository docs/
  # tree to their repository paths at this package's release tag.
  defp source_url(path, line) do
    root = Path.expand("../..", __DIR__)

    repository_path =
      path
      |> Path.expand(__DIR__)
      |> Path.relative_to(root)

    "#{@source_url}/blob/wotex-routines-v#{@version}/#{repository_path}#L#{line}"
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyxir.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
