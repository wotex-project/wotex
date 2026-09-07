[
  parallel: false,
  skipped: false,
  tools: [
    {:deps_get, command: "mix deps.get --check-locked"},
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:formatter, command: "mix format --check-formatted"},
    {:credo, command: "mix credo --strict"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:mix_audit, command: "mix deps.audit --ignore-file .mix_audit.ignore"},
    {:hex_audit, command: "mix hex.audit"},
    {:dialyzer, command: "mix dialyzer"},
    {:doctor, command: "mix doctor"},
    {:ex_doc, command: "mix docs --warnings-as-errors"},
    {:ex_unit, command: "mix coveralls"},
    {:contracts, command: "ruby bin/check-contracts"},
    {:boundary, command: "sh bin/check-boundary"},
    {:package, command: "sh bin/check-package"}
  ]
]
