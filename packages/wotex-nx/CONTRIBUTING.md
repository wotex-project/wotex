# Contributing

Changes must preserve the narrow numerical boundary, update the owning
specification and tests together, and name exact dependency revisions for new
claims. Run `WOTEX_PATH_DEPS=1 mix check` and `bin/check-boundary` before review.

Do not add model acquisition, model-serving policy, Action execution, database
ownership, application callbacks, or host framework imports.
