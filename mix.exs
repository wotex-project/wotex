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
      aliases: aliases(),
      elixirc_options: [warnings_as_errors: true],
      test_coverage: [ignore_modules: [~r/^Mix\.Tasks\./]]
    ]
  end

  def application do
    [extra_applications: [:inets, :ssl, :public_key, :crypto]]
  end

  # The root command set. Each alias names one `mix wotex.*` task (Mix
  # appends an alias's arguments to its last task); see README.md.
  defp aliases do
    [
      setup: ["deps.get", "wotex.setup"],
      affected: "wotex.affected",
      pkg: "wotex.pkg",
      def: "wotex.def",
      refs: "wotex.refs",
      impact: "wotex.impact",
      "test.affected": "wotex.test.affected",
      "check.fast": "wotex.check.fast",
      "check.affected": "wotex.check.affected",
      "check.all": "wotex.check.all",
      workspace: "wotex.workspace",
      "format.all": "wotex.format.all",
      lint: "wotex.lint",
      "dialyzer.pkg": "wotex.dialyzer",
      "docs.check": "wotex.docs.check",
      "docs.pkg": "wotex.docs",
      index: "wotex.index",
      "native.build": "wotex.native.build",
      "native.sources": "wotex.native.sources",
      "native.advisories": "wotex.native.advisories",
      "native.inspect": "wotex.native.inspect",
      "native.plan": "wotex.native.plan",
      "native.lint": "wotex.native.lint",
      "native.test": "wotex.native.test",
      "native.bench": "wotex.native.bench",
      bench: "wotex.bench",
      check: ["wotex.workspace", "wotex.check.affected"]
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.11"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:git_ops, "~> 2.12", only: :dev, runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end
end
