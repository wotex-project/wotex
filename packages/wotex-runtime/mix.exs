defmodule WotexRuntime.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"

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
      {:git_ops, "~> 2.10", only: :dev, runtime: false},
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

  defp wotex_dep do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {:wotex, "~> 0.1.0"}

      "1" ->
        {:wotex, path: Path.expand("../wotex", __DIR__), override: true}

      _value ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
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
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-runtime/CHANGELOG.md",
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-runtime"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files: ~w(.formatter.exs CHANGELOG.md LICENSE NOTICE README.md lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        {"README.md", title: "Overview"},
        {docs_path("plans/wotex-runtime-completion.md"), title: "Completion Contract"},
        {docs_path("specs/RT-C02-runtime-hardening.md"), title: "Runtime Hardening Contract"},
        {docs_path("specs/RT-C03-exposed-thing-boundary.md"),
         title: "ExposedThing Boundary Contract"},
        {docs_path("specs/RT-C04-reference-consumer.md"), title: "Reference Consumer"},
        {docs_path("specs/RT-C05-release-evidence.md"), title: "Release Evidence"},
        {docs_path("specs/RT-C06-stable-api.md"), title: "Stable API Candidate"},
        {docs_path("specs/WRT.01-consumed-thing-runtime.md"), title: "ConsumedThing Runtime"},
        {docs_path("specs/WRT.02-exposed-thing-runtime.md"), title: "ExposedThing Runtime"},
        {docs_path("specs/WRT.03-thing-level-interactions.md"), title: "Thing-level Interactions"},
        {"CHANGELOG.md", title: "Changelog"},
        {"../../docs/packages/wotex-runtime/security.md", title: "Security"},
        {"LICENSE", title: "License"}
      ],
      groups_for_extras: [
        "Completion plans": ~r/docs\/packages\/wotex-runtime\/plans/,
        "Normative specifications": ~r/docs\/packages\/wotex-runtime\/specs/,
        Reference: ~r/CHANGELOG|security|CONTRIBUTING|LICENSE/
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
      source_ref: "wotex-runtime-v#{@version}",
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

    "#{@source_url}/blob/wotex-runtime-v#{@version}/#{repository_path}#L#{line}"
  end

  defp docs_path(relative),
    do: "../../docs/packages/wotex-runtime/#{relative}"

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
