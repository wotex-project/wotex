defmodule WotexBindingMQTT.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/wotex-project/wotex-binding-mqtt"

  def project do
    [
      app: :wotex_binding_mqtt,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Caller-owned MQTT protocol binding for W3C Web of Things",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_ignore_filters: [~r{^test/support/}],
      test_coverage: [summary: [threshnew: 90]]
    ]
  end

  def application, do: [extra_applications: []]

  def cli, do: [preferred_envs: [check: :test]]

  defp deps do
    [
      wotex_dep(),
      wotex_runtime_dep(),
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :docs], runtime: false}
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
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --cover --warnings-as-errors",
        "docs --warnings-as-errors",
        "cmd bin/check-boundary",
        "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build",
        "cmd bin/check-archive"
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => @source_url,
        "Project" => "https://wotex.io",
        "W3C WoT MQTT Binding" =>
          "https://w3c.github.io/wot-binding-templates/bindings/protocols/mqtt/"
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
        "docs/specs/mqtt-values-and-client-port.md",
        "docs/specs/runtime-transport.md",
        "docs/provenance/mqtt-binding-draft-2026-07-01.md",
        "docs/provenance/mqtt-primary-sources.md",
        "docs/provenance/wot-binding-registry-2025-11-04.md"
      ],
      groups_for_extras: [
        "Library specifications": ~r/docs\/specs/,
        Provenance: ~r/docs\/provenance/
      ]
    ]
  end
end
