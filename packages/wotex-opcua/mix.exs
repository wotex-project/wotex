defmodule WotexOPCUA.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"

  def project do
    [
      app: :wotex_opcua,
      name: "Wotex OPCUA",
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
      {:telemetry, "~> 1.3"},
      {:stream_data, "~> 1.2", only: :test},
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
      "wotex.native.build": "wotex.opcua.native.build",
      "wotex.software.build": "wotex.opcua.software.build",
      "wotex.software.run": "wotex.opcua.software.run",
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"],
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp description do
    "Consumer-neutral OPCUA protocol values, operations and Web of Things Form mapping"
  end

  defp package do
    [
      name: "wotex_opcua",
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-opcua/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/wotex_opcua",
        "GitHub" => @source_url,
        "Project" => "https://wotex.io",
        "Source" => @source_url,
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-opcua",
        "W3C Thing Description 1.1" =>
          "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files:
        ~w(.formatter.exs CHANGELOG.md LICENSE NOTICE README.md config lib priv/fixtures priv/native mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        [
          "README.md",
          "CHANGELOG.md",
          Path.expand("../../docs/packages/wotex-opcua/security.md", __DIR__),
          "priv/native/runtime-guardian.md",
          "priv/native/json-codec.md",
          "priv/native/security.md",
          "priv/native/value-codec.md"
        ] ++
          Path.wildcard(
            Path.expand("../../docs/packages/wotex-opcua/{specs,plans,provenance}/*.md", __DIR__)
          ),
      groups_for_extras: [
        Native: ~r{^priv/native/},
        Specifications: ~r{/docs/packages/wotex-opcua/specs/},
        Plans: ~r{/docs/packages/wotex-opcua/plans/},
        Provenance: ~r{/docs/packages/wotex-opcua/provenance/}
      ],
      source_url: @source_url,
      source_ref: "wotex-opcua-v#{@version}",
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

    "#{@source_url}/blob/wotex-opcua-v#{@version}/#{repository_path}#L#{line}"
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyxir.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
