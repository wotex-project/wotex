[
  parallel: false,
  skipped: false,
  tools: [
    {:deps_get, command: "mix deps.get --check-locked"},
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:formatter, command: "mix format --check-formatted"},
    {:credo, command: "mix credo --strict"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:mix_audit, command: "mix deps.audit"},
    {:hex_audit, command: "mix hex.audit"},
    {:dialyzer, command: "mix dialyzer"},
    {:doctor, command: "mix doctor"},
    {:ex_doc, command: "mix docs --warnings-as-errors", env: %{"MIX_ENV" => "docs"}},
    {:ex_unit, command: "mix coveralls"}
  ]
]
