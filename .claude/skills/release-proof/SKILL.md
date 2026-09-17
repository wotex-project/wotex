---
name: release-proof
description: Apply when preparing or validating a wotex-continuum package archive, release, compatibility claim, or supply-chain evidence.
---

# Release proof workflow

Run from inside `packages/wotex-continuum/`.

1. Confirm the working tree and dependency lock are intentional.
2. Run every verification command in `packages/wotex-continuum/README.md` from
   a clean build. Use `WOTEX_PATH_DEPS=1` only for sibling packages under
   `packages/`; the package-build step MUST unset it.
3. Inspect the package file list and unpacked archive.
4. Scan source, Git history, documentation, generated docs, and archive names
   for consumer-specific material (consumer, company, and product names) and
   absolute machine paths. Sibling package names and relative paths inside this
   repository are allowed.
5. Record the source revision of this repository, the package path, archive
   SHA-256, lockfile SHA-256, WCT schema versions, vector digests, Elixir
   version, and OTP version.
6. Stop after recording local evidence. Automated agents never configure or
   remove remotes, push, create tags, publish packages, or create releases,
   regardless of whether the proof succeeds.
