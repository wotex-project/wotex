[
  parallel: false,
  skipped: false,
  tools: [
    {:deps_get, command: "mix deps.get --check-locked"},
    {:frontend_dependencies, command: "mix assets.setup"},
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:seed_data, command: "mix seed --check"},
    {:frontend, command: "mix assets.check"},
    {:storybook, command: "pnpm run storybook:build"},
    {:formatter, command: "mix format --check-formatted"},
    {:credo, command: "mix credo --strict"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:mix_audit, command: "mix deps.audit"},
    {:hex_audit, command: "mix hex.audit"},
    {:dialyzer, command: "mix dialyzer"},
    {:doctor, command: "mix doctor"},
    {:ex_doc, command: "mix docs --warnings-as-errors", env: %{"MIX_ENV" => "docs"}},
    {:ex_unit, command: "mix coveralls"},
    {:boundary, command: "elixir tools/boundary/check.exs"}
  ]
]
