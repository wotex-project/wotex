[
  parallel: false,
  skipped: false,
  tools: [
    {:compiler, "mix compile --warnings-as-errors"},
    {:formatter, "mix format --check-formatted"},
    {:unused_deps, "mix deps.unlock --check-unused"},
    {:credo, "mix credo --strict"},
    {:ex_unit, false},
    {:test, command: "mix coveralls", env: %{"MIX_ENV" => "test"}},
    {:hex_audit, "mix hex.audit"},
    {:mix_audit, "mix deps.audit"},
    {:doctor, "mix doctor --summary"},
    {:dialyzer, "mix dialyzer"},
    {:ex_doc, "mix docs --warnings-as-errors"},
    {:boundary, "elixir bin/check_boundary.exs"},
    {:package, "env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"},
    {:archive, "mix run --no-start bin/check_archive.exs"},
    {:application_free, "mix run --no-start bin/check_application_free.exs"}
  ]
]
