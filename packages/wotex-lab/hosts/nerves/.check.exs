# The host cohort's gate: `WOTEX_PATH_DEPS=1 MIX_TARGET=host mix check --no-retry`.
# The rpi4 firmware build needs the Nerves toolchain and stays an explicit lane.
[
  parallel: false,
  retry: false,
  skipped: false,
  tools: [
    {:compiler, command: "mix compile --warnings-as-errors", env: %{"MIX_ENV" => "test"}},
    {:deps_get, command: "mix deps.get --check-locked", env: %{"MIX_ENV" => "test"}},
    {:unused_deps, command: "mix deps.unlock --check-unused", env: %{"MIX_ENV" => "test"}},
    {:formatter, command: "mix format --check-formatted", env: %{"MIX_ENV" => "test"}},
    {:credo, command: "mix credo --strict", env: %{"MIX_ENV" => "test"}},
    {:ex_unit, command: "mix test", env: %{"MIX_ENV" => "test"}},
    {:doctor, false},
    {:dialyzer, false},
    {:ex_doc, false},
    {:mix_audit, false},
    {:sobelow, false},
    {:gettext, false},
    {:npm_test, false}
  ]
]
