# Changelog

All notable changes to this project are documented in this file.

## 0.1.0

- Establish the storage-neutral Thing Description Directory contract.
- Provide explicit repository, authorization, clock, and identifier ports.
- Implement registration, retrieval, replacement, Merge Patch, deletion,
  bounded listing, expiry, and Introduction mechanics.
- Return the family error shape `code`, `phase`, `path`, `message`, and
  `details` from every public failure, including `MergePatch.apply/3`. The
  directory operation and entry identifier moved into `details`.
