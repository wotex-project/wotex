defmodule WotexLabStorybook.MixProject do
  use Mix.Project

  @version "0.1.0"

  @spec project() :: keyword()
  def project do
    [
      app: :wotex_lab_storybook,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [setup: ["deps.get", "deps.compile"]],
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_file: {:no_warn, "priv/plts/dialyxir.plt"}]
    ]
  end

  @spec application() :: keyword()
  def application do
    [mod: {WotexLabStorybook.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  defp deps do
    [
      wotex_lab_dependency(),
      {:phoenix, "~> 1.8.13"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2.11"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_storybook, "== 1.3.0"},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"},
      {:lazy_html, "~> 0.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test, :docs], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp wotex_lab_dependency do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {:wotex_lab, "~> 0.1.0"}

      "1" ->
        if Mix.env() in [:dev, :test],
          do: {:wotex_lab, path: "../..", env: :dev, override: true},
          else: raise("WOTEX_PATH_DEPS is allowed only in development or test")

      _ ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
