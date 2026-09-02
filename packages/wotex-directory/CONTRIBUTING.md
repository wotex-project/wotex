# Contributing

Contributions begin with a focused issue or proposal that identifies the
affected public contract, W3C revision, compatibility consequence, and test
evidence. Changes to W3C claims require primary-source citations.

## Development

Use Elixir 1.19 and OTP 28.5. Select the sibling core checkout only through the
explicit `WOTEX_PATH_DEPS=1` environment switch.

```sh
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix format --check-formatted
WOTEX_PATH_DEPS=1 mix compile --warnings-as-errors
WOTEX_PATH_DEPS=1 mix test
MIX_ENV=docs WOTEX_PATH_DEPS=1 mix docs
WOTEX_PATH_DEPS=1 mix package
```

Public behavior changes update the owning specification, tests, and versioning
decision together. Commits use conventional lowercase subjects. Do not include
credentials, private data, internal paths, or consumer-specific names and
fixtures.
