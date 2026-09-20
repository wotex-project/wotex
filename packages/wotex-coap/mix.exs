defmodule WotexCoAP.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"

  @ssl_paths Enum.map([:ssl, :public_key, :asn1, :inets, :runtime_tools], fn app ->
               :code.lib_dir(app, :ebin) |> List.to_string()
             end)

  def project do
    [
      app: :wotex_coap,
      name: "Wotex CoAP",
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
      test_ignore_filters: [~r{^test/support/}, ~r{^test/fixtures/archive_reference_consumer\.exs$}],
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer()
    ]
  end

  def application, do: [extra_applications: [:crypto, :public_key]]

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
      {:benchee, "~> 1.5", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3.4", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:doc_shell, "== 0.4.0", only: [:dev, :test, :docs], runtime: false},
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
      dialyzer: ["compile", &load_ssl_types/1, "dialyzer"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"],
      "wotex.native.build": "wotex.coap.native.build",
      "wotex.software.build": "wotex.coap.software.build",
      "wotex.software.run": "wotex.coap.software.run",
      package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"
    ]
  end

  defp description do
    "Consumer-neutral CoAP protocol values, operations and Web of Things Form mapping"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-coap/CHANGELOG.md",
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-coap"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      files:
        ~w(.formatter.exs CHANGELOG.md LICENSE NOTICE README.md lib native priv/fixtures test/fixtures/dtls_pki test/interop test/native test/software test/support test/test_helper.exs mix.exs mix.lock)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        [
          "README.md",
          "CHANGELOG.md",
          "../../docs/packages/wotex-coap/security.md"
        ] ++
          Path.wildcard("../../docs/packages/wotex-coap/{specs,plans,provenance}/*.md") ++
          Path.wildcard("bench/output/*.md"),
      groups_for_extras: [Benchmarks: ~r/bench\/output/],
      source_url: @source_url,
      source_ref: "wotex-coap-v#{@version}",
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

    "#{@source_url}/blob/wotex-coap-v#{@version}/#{repository_path}#L#{line}"
  end

  defp load_ssl_types(_) do
    # Make the optional OTP facility available to static analysis without starting it.
    Enum.each(@ssl_paths, &Code.prepend_path/1)
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyxir.plt"},
      plt_add_apps: [:mix, :ex_unit, :ssl],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
