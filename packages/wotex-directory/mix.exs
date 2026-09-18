defmodule WotexDirectory.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wotex-project/wotex"

  def project do
    [
      app: :wotex_directory,
      name: "Wotex Directory",
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer()
    ]
  end

  def application do
    [extra_applications: []]
  end

  def cli do
    [
      preferred_envs: [
        check: :test,
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
      wotex_dependency(),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"],
      package: "run --no-start --no-compile --no-deps-check bin/check_archive.exs"
    ]
  end

  defp description do
    "Storage-neutral Thing Description Directory mechanics for W3C Web of Things consumers"
  end

  defp wotex_dependency do
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

  defp package do
    [
      files: [
        ".formatter.exs",
        "LICENSE",
        "NOTICE",
        "README.md",
        "CHANGELOG.md",
        "lib",
        "mix.exs"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/packages/wotex-directory/CHANGELOG.md",
        "Specifications" => "#{@source_url}/tree/main/docs/packages/wotex-directory"
      },
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        {"README.md", title: "Overview"},
        {docs_path("plans/wotex-directory-completion.md"), title: "Completion Contract"},
        {docs_path("specs/WTD.01-directory-contract.md"), title: "Directory contract"},
        {docs_path("specs/repository-port-evidence.md"), title: "Repository port evidence"},
        {docs_path("specs/claim-compatibility-matrix.md"), title: "Claims and compatibility"},
        {docs_path("decisions/0001-consumer-owned-runtime.md"), title: "Consumer-owned runtime"},
        {docs_path("decisions/0002-listing-and-expiry.md"), title: "Listing and expiry"},
        {docs_path("provenance/w3c-sources.md"), title: "W3C sources"},
        {"CHANGELOG.md", title: "Changelog"},
        {"../../docs/packages/wotex-directory/security.md", title: "Security"},
        {"LICENSE", title: "License"}
      ],
      groups_for_extras: [
        "Completion plans": ~r|docs/packages/wotex-directory/plans/|,
        Specifications: ~r|docs/packages/wotex-directory/specs/|,
        Decisions: ~r|docs/packages/wotex-directory/decisions/|,
        Provenance: ~r|docs/packages/wotex-directory/provenance/|,
        Reference: ~r/CHANGELOG|security|CONTRIBUTING|LICENSE/
      ],
      groups_for_modules: [
        "Public API": [Wotex.Directory],
        "Configuration and ports": [
          Wotex.Directory.Authorization,
          Wotex.Directory.Clock,
          Wotex.Directory.Clock.System,
          Wotex.Directory.Identifier,
          Wotex.Directory.Repository,
          Wotex.Directory.Service
        ],
        "Directory values": [
          Wotex.Directory.Context,
          Wotex.Directory.Cursor,
          Wotex.Directory.Entry,
          Wotex.Directory.Error,
          Wotex.Directory.Event,
          Wotex.Directory.Expiry,
          Wotex.Directory.Introduction,
          Wotex.Directory.Mutation,
          Wotex.Directory.Page,
          Wotex.Directory.Query,
          Wotex.Directory.Registration
        ],
        Mechanics: [
          Wotex.Directory.MergePatch,
          Wotex.Directory.ThingDescriptions
        ]
      ],
      source_ref: "wotex-directory-v#{@version}",
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

    "#{@source_url}/blob/wotex-directory-v#{@version}/#{repository_path}#L#{line}"
  end

  defp docs_path(relative),
    do: "../../docs/packages/wotex-directory/#{relative}"

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end
end
