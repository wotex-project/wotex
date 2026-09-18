Code.require_file("mix_tasks/check_runner.ex", __DIR__)

defmodule WotexLabWorkbench.MixProject do
  use Mix.Project

  @version "0.1.0"

  @spec project() :: keyword()
  def project do
    [
      app: :wotex_lab_workbench,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_file: {:no_warn, "priv/plts/dialyxir.plt"}, plt_add_apps: [:mix, :ex_unit]],
      releases: [wotex_lab_workbench: [include_executables_for: [:unix], strip_beams: true]]
    ]
  end

  @spec application() :: keyword()
  def application do
    [mod: {WotexLabWorkbench.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  @spec cli() :: keyword()
  def cli do
    [preferred_envs: [check: :test, coveralls: :test, "test.cover": :test]]
  end

  # The host consumes the Lab and the WoTEx profile packages as artifacts.
  # `WOTEX_PATH_DEPS=1` is the family's single development switch: it points
  # at the Lab package two directories up and its sibling packages in
  # `packages/`, and is refused outside dev, test and docs. It never proves
  # artifact adoption; release paths use Hex requirements only.
  defp deps do
    [
      wotex_dependency(:wotex_lab, "wotex-lab", path: "../.."),
      wotex_dependency(:wotex, "wotex"),
      wotex_dependency(:wotex_nx, "wotex-nx"),
      wotex_dependency(:wotex_runtime, "wotex-runtime"),
      wotex_dependency(:wotex_directory, "wotex-directory"),
      wotex_dependency(:wotex_continuum, "wotex-continuum"),
      wotex_dependency(:wotex_binding_http, "wotex-binding-http"),
      wotex_dependency(:wotex_binding_mqtt, "wotex-binding-mqtt"),
      {:ex_maude, "~> 0.4.1"},
      {:nx, "~> 0.13.1"},
      {:explorer, "~> 0.12.0"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.1"},
      {:prom_ex, "~> 1.12.0"},
      {:beamlens, "== 0.3.1"},
      {:phoenix, "~> 1.8.13"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2.11"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
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

  defp wotex_dependency(app, directory, opts \\ []) do
    {path, opts} = Keyword.pop(opts, :path, "../../../#{directory}")

    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {app, "~> 0.1.0", opts}

      "1" ->
        if Mix.env() in [:dev, :test, :docs] do
          {app, [path: Path.expand(path, __DIR__), env: :dev, override: true] ++ opts}
        else
          raise "WOTEX_PATH_DEPS is allowed only in development, test or docs"
        end

      _ ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      check: [&WotexLabWorkbench.CheckRunner.run/1],
      setup: ["deps.get", "deps.compile"],
      "test.cover": ["coveralls"]
    ]
  end
end
