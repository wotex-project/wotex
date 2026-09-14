[
  parallel: false,
  skipped: false,
  tools: [
    {:deps_get, command: "mix deps.get --check-locked"},
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:formatter, command: "mix format --check-formatted"},
    {:mix_audit, command: "mix deps.audit"},
    {:credo, command: "mix credo --strict"},
    {:doctor, command: "mix doctor"},
    {:sobelow, false},
    {:ex_doc, command: "mix docs --warnings-as-errors", env: %{"MIX_ENV" => "docs"}},
    {:ex_unit, false},
    {:dialyzer, command: "mix dialyzer"},
    {:gettext, false},
    {:npm_test, false},
    {:coverage, command: "mix coveralls", env: %{"MIX_ENV" => "test"}},
    {:hex_audit, command: "mix hex.audit"},
    {:boundary, command: "elixir bin/check_boundary.exs"},
    {:application, command: "mix run --no-start bin/check_application_free.exs"},
    {:package, command: "mix package"},
    {:archive, command: "mix run --no-start bin/check_archive.exs"},
    {:diff, command: "git diff --check"}
  ]
]
