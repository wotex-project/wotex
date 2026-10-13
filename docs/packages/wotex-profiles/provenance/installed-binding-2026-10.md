# Installed profile-binding milestone

Version: 0.1.0. Updated: 2026-10-13.

Source: repository commit `9ae759ed`, package `packages/wotex-profiles`.
Binding.digest/2, new/2, to_map/2 and reference/2 are implemented. The compiler,
capture, checked/projection and report/proposal shapes are frozen entry artifacts;
their constructor/compiler/interpreter APIs remain planned. Structural-schema
resolution and schema-valid fixtures do not establish those planned behaviors.

The source's full gate passed with Elixir 1.20.2 / OTP 29.0.4: 31 tests, 96.3%
coverage against the unchanged 95% floor, Dialyzer zero errors/skips, compilation
with warnings as errors, formatting, Credo, Doctor, ExDoc, locked/unused
requirements, both dependency audits, boundary, archive and passive-load checks.
Binding tests independently verify the Python-derived registration digest,
changed selector/operation/capture/decoder identities, closed native values and
unsupported mechanic refusals. No decoder or transport was started.

After consumer documentation changed, the archive check was rerun against the
final source bytes. Its exact cohort was:

| Archive | SHA-256 |
| --- | --- |
| wotex | 77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61 |
| wotex-runtime | 7c5412ea01dab311357a09276030ca005470c9bd8b0f471e0da3fb8ec5e4b1b4 |
| wotex-profiles | 6ac2c12f3870251625f624eff2b3d5b283b8f6394962034ebff218587f09beca |

Both isolated consumer locks were
`b54ba2c3f013c54417dbed832ff43071f55f265ed2d98cb9ec3f2079b8e31ff2`.
Both consumers passed their 3 existing reader/exact-unit tests. These consumer
cases do not yet exercise the new Binding API; its current executable evidence
is the focused package suite. The archive ships the new module and frozen
contracts/schemas/vectors, with every member matched to source bytes.

`mix docs.check` resolved 505 Markdown files and verified the generated catalogue.
Git whitespace and staged-scope checks passed. The historical reader/unit
cohorts remain retained; they were not promoted to this successor by editing
identities. No native/physical suite or performance benchmark was run.
