[
  parallel: false,
  skipped: false,
  tools: [
    {:deps_get, command: "mix deps.get --check-locked"},
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:formatter, command: "mix format --check-formatted"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:credo, command: "mix credo --strict"},
    {:ex_unit, false},
    {:coverage, command: "mix coveralls", env: %{"MIX_ENV" => "test"}},
    {:hex_audit, command: "mix hex.audit"},
    {:mix_audit, command: "mix deps.audit"},
    {:doctor, command: "mix doctor"},
    {:dialyzer, command: "mix dialyzer"},
    {:ex_doc, command: "mix docs --warnings-as-errors"},
    {:boundary, command: "elixir bin/check_boundary.exs"},
    {:package, command: "mix run --no-start bin/check_package.exs", env: %{"MIX_ENV" => "prod"}}
  ]
]
