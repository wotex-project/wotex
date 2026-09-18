defmodule WotexBindingMQTT.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"
  @docs_root "../../docs/packages/wotex-binding-mqtt"

  def project do
    [
      app: :wotex_binding_mqtt,
      name: "Wotex MQTT Binding",
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

  def application, do: [extra_applications: []]

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.lcov": :test,
        "test.cover": :test,
        check: :test
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
      {:benchee, "~> 1.5", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3.4", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :docs], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
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
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp description do
    "Immutable MQTT command mapping and caller-owned transport adaptation for W3C Web of Things"
  end

  defp package do
    [
      name: "wotex_binding_mqtt",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-binding-mqtt/CHANGELOG.md",
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-binding-mqtt"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files: ~w(.formatter.exs CHANGELOG.md LICENSE NOTICE README.md lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        [
          {"README.md", title: "Overview"},
          {doc("plans/wotex-binding-mqtt-completion.md"), title: "Completion Contract"},
          {doc("specs/WBM.01-values-and-client-port.md"), title: "Values and client port"},
          {doc("specs/WBM.02-form-mapping.md"), title: "Form mapping"},
          {doc("specs/WBM.03-runtime-transport.md"), title: "Runtime transport"},
          {doc("plans/WBM-C01-operation-inventory.md"), title: "Operation inventory"},
          {doc("plans/WBM-C02-client-lifecycle.md"), title: "Client lifecycle proof"},
          {doc("plans/WBM-C03-limits-security.md"), title: "Limits and security"},
          {doc("reference-consumer-inventory.md"), title: "Archive reference consumer"},
          {doc("release-candidate-inventory.md"), title: "Release candidate"},
          {doc("runtime-baseline.md"), title: "Runtime baseline"},
          {doc("provenance/mqtt-binding-draft-2026-07-01.md"), title: "MQTT binding draft"},
          {doc("provenance/mqtt-primary-sources.md"), title: "MQTT primary sources"},
          {doc("provenance/wot-binding-registry-2025-11-04.md"), title: "Binding Registry status"},
          {"CHANGELOG.md", title: "Changelog"},
          {"../../docs/packages/wotex-binding-mqtt/security.md", title: "Security"},
          {"LICENSE", title: "License"},
          {"NOTICE", title: "Notices"}
        ] ++ Path.wildcard("bench/output/*.md"),
      groups_for_extras: [
        "Completion plans": ~r/docs\/packages\/wotex-binding-mqtt\/plans/,
        "Library specifications": ~r/docs\/packages\/wotex-binding-mqtt\/specs/,
        Provenance: ~r/docs\/packages\/wotex-binding-mqtt\/provenance/,
        Benchmarks: ~r/bench\/output/,
        Reference: ~r/CHANGELOG|security|CONTRIBUTING|LICENSE/
      ],
      groups_for_modules: [
        "Public API": [Wotex.Binding.MQTT],
        "Binding values": [
          Wotex.Binding.MQTT.Broker,
          Wotex.Binding.MQTT.Command,
          Wotex.Binding.MQTT.Delivery,
          Wotex.Binding.MQTT.Error,
          Wotex.Binding.MQTT.QoS,
          Wotex.Binding.MQTT.Topic,
          Wotex.Binding.MQTT.TransportConfig
        ],
        "Mapping and transport": [
          Wotex.Binding.MQTT.Client,
          Wotex.Binding.MQTT.JSON,
          Wotex.Binding.MQTT.Mapping,
          Wotex.Binding.MQTT.Transport
        ]
      ],
      source_ref: "wotex-binding-mqtt-v#{@version}",
      source_url: @source_url,
      source_url_pattern: &source_url/2,
      formatters: ["html", "markdown", "epub"]
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

    "#{@source_url}/blob/wotex-binding-mqtt-v#{@version}/#{repository_path}#L#{line}"
  end

  defp doc(path), do: Path.join(@docs_root, path)

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
