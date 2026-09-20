defmodule WotexBindingHTTP.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"
  @docs_root "../../docs/packages/wotex-binding-http"

  def project do
    [
      app: :wotex_binding_http,
      name: "Wotex HTTP Binding",
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
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
      {:benchee, "~> 1.5", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3.4", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:doctest_formatter, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:doc_shell, "== 0.4.0", only: [:dev, :test, :docs], runtime: false},
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
          {:wotex, path: Path.expand("../wotex", __DIR__), env: :dev, override: true}
        else
          raise "WOTEX_PATH_DEPS is allowed only in development, test or docs"
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
          {:wotex_runtime,
           path: Path.expand("../wotex-runtime", __DIR__), env: :dev, override: true}
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
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp package do
    [
      name: "wotex_binding_http",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-binding-http/CHANGELOG.md",
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-binding-http"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files: ~w(.formatter.exs CHANGELOG.md LICENSE NOTICE README.md lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "wotex-binding-http-v#{@version}",
      source_url: @source_url,
      source_url_pattern: &source_url/2,
      formatters: ["html", "epub", "markdown"],
      extras:
        [
          {"README.md", title: "Overview"},
          {"CHANGELOG.md", title: "Changelog"},
          {"LICENSE", title: "License"},
          {"NOTICE", title: "Notices"},
          {doc("security.md"), title: "Security"},
          {doc("client-lifecycle-inventory.md"), title: "Client lifecycle inventory"},
          {doc("http-operation-inventory.md"), title: "HTTP operation inventory"},
          {doc("limits-security-inventory.md"), title: "Limits and security inventory"},
          {doc("reference-consumer-inventory.md"), title: "Archive reference consumer"},
          {doc("release-candidate-inventory.md"), title: "Release-candidate inventory"},
          {doc("standards-baseline.md"), title: "Standards baseline"},
          {doc("runtime-baseline.md"), title: "Runtime baseline"},
          {doc("plans/wotex-binding-http-completion.md"), title: "Completion Contract"},
          {doc("specs/WBH.01-http-transport.md"), title: "HTTP transport"},
          {doc("specs/WBH.02-client-port-and-values.md"), title: "Client port and values"},
          {doc("specs/WBH.03-sse-subscriptions.md"), title: "SSE subscriptions"}
        ] ++ Path.wildcard("bench/output/*.md"),
      groups_for_extras: [
        "Completion plans": ~r/docs\/packages\/wotex-binding-http\/plans/,
        Security: ~r/docs\/packages\/wotex-binding-http\/security/,
        "Normative package specifications": ~r/docs\/packages\/wotex-binding-http\/specs/,
        "Contract evidence":
          ~r/docs\/packages\/wotex-binding-http\/((client-lifecycle|http-operation|limits-security|reference-consumer|release-candidate)-inventory|(standards|runtime)-baseline)/,
        Benchmarks: ~r/bench\/output/
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

  # Links modules and the specification extras under the repository docs/
  # tree to their repository paths at this package's release tag.
  defp source_url(path, line) do
    root = Path.expand("../..", __DIR__)

    repository_path =
      path
      |> Path.expand(__DIR__)
      |> Path.relative_to(root)

    "#{@source_url}/blob/wotex-binding-http-v#{@version}/#{repository_path}#L#{line}"
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp doc(path), do: Path.join(@docs_root, path)

  defp dialyzer do
    [
      flags: [:error_handling, :extra_return, :missing_return, :unmatched_returns, :unknown],
      plt_add_apps: [:mix, :ex_unit]
    ]
  end
end
