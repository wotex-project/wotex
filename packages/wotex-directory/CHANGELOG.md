# Changelog

All notable changes to this project are documented in this file.

## 0.1.0

- Exercise raising context errors through dynamic invalid-input vectors for
  both arities, preserving typed codes without intentional static type warnings.

- Retain exact Decimal 3.1.1 lock and bounded parser regressions while removing
  the stale, unmatched advisory suppression; all advisory checks remain active.

- Establish the storage-neutral Thing Description Directory contract.
- Provide explicit repository, authorization, clock, and identifier ports.
- Implement registration, retrieval, replacement, Merge Patch, deletion,
  bounded listing, expiry, and Introduction mechanics.
- Return the family error shape `code`, `phase`, `path`, `message`, and
  `details` from every public failure, including `MergePatch.apply/3`. The
  directory operation and entry identifier moved into `details`.
- Adopt the family limit vocabulary `max_page_limit`, `max_expiry_batch_limit`,
  `max_patch_depth`, `max_patch_nodes`, `max_limit`, `max_depth`, and
  `max_nodes`, and forward all five core limits through
  `thing_description_options`.
- Page listings with an opaque keyset cursor. `Query` carries `cursor` and
  `limit`, `Page` carries `entries`, `next_cursor`, and `collection_revision`,
  the repository `list` callback receives the decoded cursor, and wall-clock
  expiry between pages no longer ends a page chain.
- Document the repository transaction and isolation expectations, the lost
  named-registration create race and its retry, and `Wotex.Directory.Clock.System`
  as an explicit opt-in default.
