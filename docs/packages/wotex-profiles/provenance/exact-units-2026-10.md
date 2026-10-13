# Exact profile-unit arithmetic archive milestone

Version: 0.1.0. Updated: 2026-10-13.

Source: repository commit `b3fff143`, package `packages/wotex-profiles`.
The source files were verified immediately before the local commits forming
this snapshot; no archive member changed between verification and that commit.
This is a successor to [the reader milestone](reader-2026-10.md), which remains
historical evidence for its earlier exact source and archive cohort.

| Archive | SHA-256 |
| --- | --- |
| wotex | 77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61 |
| wotex-runtime | 7c5412ea01dab311357a09276030ca005470c9bd8b0f471e0da3fb8ec5e4b1b4 |
| wotex-profiles | 42b42d1227707c06591a7b6052b58dbfbe96fc110fbb71bda9994c1fec3b4e30 |

Each independent consumer lock had SHA-256
`b54ba2c3f013c54417dbed832ff43071f55f265ed2d98cb9ec3f2079b8e31ff2`.
Builds unset the sibling switch; consumers used only extracted selected archives.
The owning archive tool compared every profile archive member with source bytes.

Executed with Elixir 1.20.2 / OTP 29.0.4:

- `mix pkg wotex-profiles check --no-retry`: all 15 configured tools passed;
  27 tests, 96.1% coverage against the unchanged 95% floor, Dialyzer zero
  errors/skips, compile warnings as errors, formatting, Credo, Doctor, docs,
  dependency lock/unused checks, both audits, boundary, archive and passive
  application checks.
- Both isolated consumers passed 3 tests each. Each retained original/semantic
  identities and exercised exact fractional coordinates, mismatched quantity
  refusal and repeating-fraction refusal through the archived public APIs.
- Independent Python Fraction-derived vectors cover 17 named numeric/domain
  cases. Additional tests cover signed sums, cross products, denominator/power
  and aggregate input limits, native malformed inputs, and round trips under
  a deliberately reduced ambient Decimal context.
- Reader regressions distinguish malformed native JSON from resource excess,
  and preserve inert C02 byte literals without asserting executable byte-domain
  support. `mix docs.check` resolved 504 Markdown files; catalogue current.

Full root tooling evidence is retained in the preceding reader milestone.
No native or physical suite was selected for these passive arithmetic changes.
No performance benchmark was run. Compiler, capture/report interpretation,
authoring, consumer admission and physical qualification remain open obligations.
