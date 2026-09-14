defmodule WotexBindingHTTP.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex-binding-http"

  def project do
    [
      app: :wotex_binding_http,
      name: "Wotex HTTP Binding",
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Caller-owned HTTP and Server-Sent Events binding for Wotex Runtime",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_ignore_filters: [~r{^test/support/}],
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer()
    ]
  end

  def application, do: [extra_applications: []]

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.lcov": :test
      ]
    ]
  end

  defp deps do
    [
      wotex_dep(),
      wotex_runtime_dep(),
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.10", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:doctest_formatter, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test, :docs], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.3", only: :test}
    ]
  end

  defp wotex_dep do
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

  defp wotex_runtime_dep do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {:wotex_runtime, "~> 0.1.0"}

      "1" ->
        if Mix.env() in [:dev, :test, :docs] do
          {:wotex_runtime, path: Path.expand("../wotex-runtime", __DIR__), override: true}
        else
          raise "WOTEX_PATH_DEPS is allowed only in non-production development environments"
        end

      _value ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
    end
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Documentation" => "https://hexdocs.pm/wotex_binding_http",
        "GitHub" => @source_url,
        "Wotex" => "https://wotex.io",
        "W3C Web of Things" => "https://www.w3.org/WoT/"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files:
        ~w(.formatter.exs CHANGELOG.md CODE_OF_CONDUCT.md CONTRIBUTING.md GOVERNANCE.md LICENSE NOTICE README.md SECURITY.md docs/client-lifecycle-inventory.md docs/http-operation-inventory.md docs/limits-security-inventory.md docs/plans docs/runtime-baseline.md docs/standards-baseline.md docs/specs lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html", "epub", "markdown"],
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"],
        NOTICE: [title: "Notices"],
        "docs/client-lifecycle-inventory.md": [title: "Client lifecycle inventory"],
        "docs/http-operation-inventory.md": [title: "HTTP operation inventory"],
        "docs/limits-security-inventory.md": [title: "Limits and security inventory"],
        "docs/standards-baseline.md": [title: "Standards baseline"],
        "docs/runtime-baseline.md": [title: "Runtime baseline"],
        "docs/plans/wotex-binding-http-completion.md": [title: "Completion Contract"],
        "docs/specs/WBH.01-http-transport.md": [title: "HTTP transport"],
        "docs/specs/WBH.02-client-port-and-values.md": [title: "Client port and values"],
        "docs/specs/WBH.03-sse-subscriptions.md": [title: "SSE subscriptions"]
      ],
      groups_for_extras: [
        "Completion plans": ~r/docs\/plans/,
        "Normative package specifications": ~r/docs\/specs/,
        "Contract evidence":
          ~r/docs\/((client-lifecycle|http-operation|limits-security)-inventory|(standards|runtime)-baseline)/
      ],
      groups_for_modules: [
        "Public API": [Wotex.Binding.HTTP, Wotex.Binding.HTTP.Client],
        "HTTP values": [
          Wotex.Binding.HTTP.Config,
          Wotex.Binding.HTTP.EmptyBody,
          Wotex.Binding.HTTP.Error,
          Wotex.Binding.HTTP.Headers,
          Wotex.Binding.HTTP.Notification,
          Wotex.Binding.HTTP.Request,
          Wotex.Binding.HTTP.Response,
          Wotex.Binding.HTTP.SSE.Event,
          Wotex.Binding.HTTP.Subscription
        ],
        "Runtime integration": [Wotex.Binding.HTTP.Transport]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp dialyzer do
    [
      flags: [:error_handling, :extra_return, :missing_return, :unmatched_returns, :unknown],
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "priv/plts/core",
      plt_local_path: "priv/plts/local"
    ]
  end
end
