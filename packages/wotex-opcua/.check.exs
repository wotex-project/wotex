[
  parallel: false,
  retry: false,
  skipped: false,
  tools: [
    {:compiler, command: "mix compile --warnings-as-errors"},
    {:deps_get, command: "mix deps.get --check-locked"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:formatter, command: "mix format --check-formatted"},
    {:mix_audit, command: "mix deps.audit"},
    {:hex_audit, command: "mix hex.audit"},
    {:credo, command: "mix credo --strict"},
    {:doctor, command: "mix doctor --summary"},
    {:sobelow, false},
    {:ex_doc, command: "mix docs --warnings-as-errors", env: %{"MIX_ENV" => "docs"}},
    {:ex_unit, false},
    {:coverage,
     command: "mix coveralls",
     env: %{
       "MIX_ENV" => "test",
       "WOTEX_REQUIRE_NATIVE_BUILD" => "1",
       "WOTEX_NATIVE_BUILD_WORKSPACE" => Path.join(System.tmp_dir!(), "wotex-opcua-check")
     }},
    {:dialyzer, command: "mix dialyzer"},
    # First-party C, C++ and Rust code through the root tasks (see
    # tooling/packages.yaml): changed-line formatting, static analysis and the
    # native tests, which build into a cached workspace outside the repository.
    {:native_format,
     command: "mix native.lint --package wotex-opcua",
     cd: "../..",
     fix: "mix native.lint --fix --package wotex-opcua"},
    {:native_lint,
     command: "mix native.lint --tidy --no-format --no-clippy --package wotex-opcua",
     cd: "../..",
     deps: [:native_format]},
    {:native_test,
     command: "mix native.test --package wotex-opcua", cd: "../..", deps: [:native_lint]},
    {:native_custody, command: "mix run --no-start bin/check_native_custody.exs"},
    {:package, command: "env -u WOTEX_PATH_DEPS MIX_ENV=dev mix hex.build"},
    {:archive, command: "mix run --no-start bin/check_archive.exs", deps: [coverage: [status: 0]]},
    {:application_free, command: "mix run --no-start bin/check_application_free.exs"},
    {:diff, command: "git diff --check"},
    {:gettext, false},
    {:npm_test, false}
  ]
]
