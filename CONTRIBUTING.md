# Contributing

WoTEx is a family of independent packages in one repository. Each package has
its own contract in `packages/<name>/CLAUDE.md` and its own specifications
under `docs/packages/<name>/specs/`. Read both before changing a package.

Begin a behavior change with a normative specification or an accepted issue
that identifies the affected requirement and its evidence vector. Use exact
W3C Web of Things terminology. A standards claim must identify the exact
revision, operation, assumptions, fixture digest and result. Unsupported cells
remain absent rather than documented as planned support.

Run the changed package's gate before proposing a change, from inside its
directory:

```sh
cd packages/<name>
WOTEX_PATH_DEPS=1 mix check --no-retry
```

Run the same gate in every package that depends on the one you changed. Add
tests beside the package tests, not in repository-level tooling.

Do not add a database, application callback, hidden process, consumer-specific
namespace, credential store, transport connection or physical-state authority
to a library package. Do not add an umbrella project. Do not make code read
from `docs/`.

Commits use a conventional prefix and a natural sentence, without
specification or work-package identifiers, and carry the contributor's own
identity. Open an issue before a compatibility-affecting change.
