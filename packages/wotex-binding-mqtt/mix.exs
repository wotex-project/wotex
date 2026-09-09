defmodule WotexBindingMQTT.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex-binding-mqtt"

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
        "test.cover": :test
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
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/wotex_binding_mqtt",
        "Project" => "https://wotex.io",
        "Source" => @source_url,
        "W3C WoT MQTT Binding" =>
          "https://w3c.github.io/wot-binding-templates/bindings/protocols/mqtt/"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files:
        ~w(.claude .formatter.exs AGENTS.md CHANGELOG.md CLAUDE.md CODE_OF_CONDUCT.md CONTRIBUTING.md GOVERNANCE.md LICENSE NOTICE README.md SECURITY.md docs/plans docs/provenance docs/specs lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "docs/plans/wotex-binding-mqtt-completion.md": [title: "Completion Contract"],
        "docs/specs/WBM.01-values-and-client-port.md": [title: "Values and client port"],
        "docs/specs/WBM.02-form-mapping.md": [title: "Form mapping"],
        "docs/specs/WBM.03-runtime-transport.md": [title: "Runtime transport"],
        "docs/provenance/mqtt-binding-draft-2026-07-01.md": [title: "MQTT binding draft"],
        "docs/provenance/mqtt-primary-sources.md": [title: "MQTT primary sources"],
        "docs/provenance/wot-binding-registry-2025-11-04.md": [title: "Binding Registry status"],
        "CHANGELOG.md": [title: "Changelog"],
        "SECURITY.md": [title: "Security"],
        "CONTRIBUTING.md": [title: "Contributing"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Completion plans": ~r/docs\/plans/,
        "Library specifications": ~r/docs\/specs/,
        Provenance: ~r/docs\/provenance/,
        Reference: ~r/CHANGELOG|SECURITY|CONTRIBUTING|LICENSE/
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
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html", "markdown", "epub"]
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
