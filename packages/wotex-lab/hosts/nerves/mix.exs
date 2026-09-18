defmodule WotexLabNerves.MixProject do
  use Mix.Project

  @app :wotex_lab_nerves
  @version "0.1.0"

  @spec project() :: keyword()
  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}]
    ]
  end

  @spec cli() :: keyword()
  def cli, do: [preferred_envs: [check: :test], preferred_targets: [run: :host, test: :host]]

  @spec application() :: keyword()
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {WotexLabNerves.Application, []}
    ]
  end

  defp deps do
    [
      {:nerves, "1.15.0", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:nerves_runtime, "~> 0.13.0"},
      {:nerves_system_rpi4, "2.1.1", runtime: false, targets: :rpi4},
      wotex_dependency(:wotex, "wotex"),
      wotex_dependency(:wotex_nx, "wotex-nx"),
      wotex_dependency(:wotex_runtime, "wotex-runtime"),
      wotex_dependency(:wotex_lab, "wotex-lab"),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false}
    ]
  end

  defp wotex_dependency(app, directory) do
    case System.get_env("WOTEX_PATH_DEPS") do
      nil ->
        {app, "~> 0.1.0"}

      "1" ->
        if Mix.env() in [:dev, :test, :docs] do
          path = if directory == "wotex-lab", do: "../..", else: "../../../#{directory}"
          {app, path: Path.expand(path, __DIR__), env: :dev, override: true}
        else
          raise "WOTEX_PATH_DEPS is allowed only in development, test or docs"
        end

      _ ->
        raise "WOTEX_PATH_DEPS must be unset or equal to 1"
    end
  end

  defp release do
    [
      overwrite: true,
      cookie: "wotex_lab_nerves",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod
    ]
  end
end
