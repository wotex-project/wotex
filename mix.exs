defmodule WotexWorkspace.MixProject do
  use Mix.Project

  # Repository-level tooling only. This project is never published, is not an
  # umbrella and depends on no package under packages/. It reads
  # tooling/packages.yaml and drives each package's own Mix project through
  # `System.cmd/3`; package code never runs in this VM.
  def project do
    [
      app: :wotex_workspace,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      deps: deps(),
      elixirc_options: [warnings_as_errors: true],
      test_coverage: [ignore_modules: [~r/^Mix\.Tasks\./]]
    ]
  end

  def application do
    [extra_applications: [:inets, :ssl, :public_key, :crypto]]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.11"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end
end
