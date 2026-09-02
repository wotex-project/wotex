defmodule WotexDirectory.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/wotex-project/wotex-directory"

  def project do
    [
      app: :wotex_directory,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: "Storage-neutral W3C Web of Things Discovery directory mechanics",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wotex.io",
      test_coverage: [
        summary: [threshold: 90],
        ignore_modules: [
          Wotex.Directory.FailureRepository,
          Wotex.Directory.Fixtures,
          Wotex.Directory.MemoryRepository,
          Wotex.Directory.TestAuthorization,
          Wotex.Directory.TestClock,
          Wotex.Directory.TestIdentifier,
          Wotex.Directory.TestService
        ]
      ]
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      wotex_dependency(),
      {:ex_doc, "~> 0.38", only: :docs, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp aliases do
    [package: "cmd env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"]
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
        ".claude",
        ".formatter.exs",
        "AGENTS.md",
        "CLAUDE.md",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "GOVERNANCE.md",
        "LICENSE",
        "NOTICE",
        "README.md",
        "SECURITY.md",
        "docs",
        "lib",
        "mix.exs"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "Homepage" => "https://wotex.io",
        "Source" => @source_url
      },
      maintainers: ["Wotex Project Maintainers"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/specs/WTD.01-directory-contract.md",
        "docs/decisions/0001-consumer-owned-runtime.md",
        "docs/decisions/0002-listing-and-expiry.md",
        "docs/provenance/w3c-sources.md"
      ],
      groups_for_extras: [
        Specifications: ~r|docs/specs/|,
        Decisions: ~r|docs/decisions/|,
        Provenance: ~r|docs/provenance/|
      ],
      source_ref: "v#{@version}"
    ]
  end
end
