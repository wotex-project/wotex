# RT-C05: Release evidence contract

Packet `RT-C05` defines the evidence required before `wotex_runtime 0.1.0` can
be considered a public release candidate. Publication remains a manual
maintainer action.

## Package archive

The package lane requires the exact core archive:

```bash
WOTEX_CORE_ARCHIVE=/absolute/path/wotex-0.1.0.tar \
  elixir bin/check_package.exs
```

The checker builds and unpacks the Runtime archive, verifies required project,
license, security, plan, specification, catalogue, and source content, and
rejects local trackers, repository controls, tests, build products, generated
documentation, and static-analysis state. These checks cover required and
forbidden classes of content without treating the complete archive member list
as a stable API.

The checker then creates a separate Mix consumer from the unpacked Runtime and
core archives. It resolves and locks external dependencies, compiles with
warnings as errors, and exercises a supported ExposedThing dispatch and its
typed missing-handler result. It also verifies that Runtime loads without an
application callback and that its BEAM files come from the consumer build.

The lane prints SHA-256 digests for both archives and the generated consumer
lock. A successful run proves the inspected artifacts. It does not prove a Hex
registry install or authorize publication.

## Explicit verification lanes

Run these checks separately from `mix check` and record each result against the
exact source commit and toolchain:

```bash
WOTEX_PATH_DEPS=1 mix docs --warnings-as-errors
WOTEX_PATH_DEPS=1 mix credo --strict
WOTEX_PATH_DEPS=1 mix doctor
WOTEX_PATH_DEPS=1 mix coveralls
WOTEX_PATH_DEPS=1 mix dialyzer
WOTEX_PATH_DEPS=1 mix deps.unlock --check-unused
WOTEX_PATH_DEPS=1 mix deps.audit
WOTEX_PATH_DEPS=1 mix hex.audit
WOTEX_PATH_DEPS=1 elixir bin/check_boundary.exs
```

The supported compatibility floor is Elixir 1.18 on OTP 27. The repository
gate must pass on one available Elixir 1.18/OTP 27 pair and the current project
toolchain before recording the candidate. A successful pair proves only that
pair; it does not prove every version admitted by the Mix requirement.

Mutable command output and artifact digests belong in the ignored local tracker
defined by the completion contract. They are not normative package content.
