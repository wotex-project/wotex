[
  parallel: false,
  skipped: false,
  tools: [
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:unused_deps, false},
    {:formatter, command: "mix format --check-formatted"},
    {:mix_audit, false},
    {:credo, false},
    {:doctor, false},
    {:sobelow, false},
    {:ex_doc, false},
    {:ex_unit, command: "mix test"},
    {:dialyzer, false},
    {:gettext, false},
    {:npm_test, false}
  ]
]
