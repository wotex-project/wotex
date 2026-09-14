[
  parallel: false,
  skipped: false,
  tools: [
    {:deps_get, command: "mix deps.get --check-locked"},
    {:compiler, command: "mix do clean + compile --warnings-as-errors"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:formatter, command: "mix format --check-formatted"},
    {:mix_audit, command: "mix deps.audit"},
    {:credo, command: "mix credo --strict"},
    {:doctor, command: "mix doctor"},
    {:sobelow, false},
    {:ex_doc, command: "mix docs --warnings-as-errors"},
    {:ex_unit, false},
    {:dialyzer, command: "mix dialyzer --force-check"},
    {:gettext, false},
    {:npm_test, false},
    {:coverage, command: "mix coveralls", env: %{"MIX_ENV" => "test"}},
    {:hex_audit, command: "mix hex.audit"},
    {:application_free, command: "mix run --no-start bin/check_application_free.exs"},
    {:archive, command: "mix run --no-start bin/check_archive.exs"},
    {:diff, command: "git diff --check"}
  ]
]
