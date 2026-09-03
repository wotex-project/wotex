[
  parallel: false,
  skipped: false,
  tools: [
    {:deps_get, command: "mix deps.get"},
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:formatter, command: "mix format --check-formatted"},
    {:credo, command: "mix credo --strict"},
    {:unused_dependencies, command: "mix deps.unlock --check-unused"},
    {:mix_audit, command: "mix deps.audit"},
    {:hex_audit, command: "mix hex.audit"},
    {:dialyzer, command: "mix dialyzer"},
    {:doctor, command: "mix doctor"},
    {:ex_doc, command: "mix docs --warnings-as-errors"},
    {:ex_unit, command: "mix coveralls"},
    {:boundary, command: "scripts/check_public_boundary.sh"},
    {:archive, command: "bin/check-archive"}
  ]
]

