[
  parallel: false,
  retry: false,
  skipped: false,
  tools: [
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:deps_get, command: "mix deps.get --check-locked"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:formatter, command: "mix format --check-formatted"},
    {:mix_audit, command: "mix deps.audit --ignore-file .mix_audit.ignore"},
    {:hex_audit, command: "mix hex.audit"},
    {:credo, command: "mix credo --strict"},
    {:doctor, command: "mix doctor --summary"},
    {:sobelow, false},
    {:ex_doc, command: "mix docs --warnings-as-errors", env: %{"MIX_ENV" => "docs"}},
    {:ex_unit, false},
    {:coverage, command: "mix coveralls", env: %{"MIX_ENV" => "test"}},
    {:dialyzer, command: "mix dialyzer"},
    {:contracts, command: "mix run --no-start bin/check_contracts.exs"},
    {:graph, command: "mix run --no-start bin/check_graph.exs"},
    {:api_surface, command: "mix run --no-start bin/generate_api_surface.exs --check"},
    {:nerves_source, command: "elixir bin/check_nerves_source.exs"},
    {:boundary, command: "elixir bin/check_boundary.exs"},
    {:package, command: "mix run --no-start bin/check_package.exs", deps: [coverage: [status: 0]]},
    {:diff, command: "git diff --check"},
    {:gettext, false},
    {:npm_test, false}
  ]
]
