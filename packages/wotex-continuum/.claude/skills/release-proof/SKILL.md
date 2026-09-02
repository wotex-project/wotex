---
name: release-proof
description: Apply when preparing or validating a package archive, release, compatibility claim, or supply-chain evidence.
---

# Release proof workflow

1. Confirm the working tree and dependency lock are intentional.
2. Run every verification command in `README.md` from a clean build.
3. Inspect the package file list and unpacked archive.
4. Scan source, Git history, documentation, generated docs, and archive names
   for consumer-specific material and local paths.
5. Record the source revision, archive SHA-256, lockfile SHA-256, WCT schema
   versions, vector digests, Elixir version, and OTP version.
6. Do not publish when any input or command is incomplete.
