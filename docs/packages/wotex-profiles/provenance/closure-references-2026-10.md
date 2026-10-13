# Reachable closure reference evidence

Repository commit `5626facf`, package `packages/wotex-profiles`, adds public
Compiler.references/3. It rechecks static channels and selected input closure,
returns the exact sorted reference array used by closure_sha256, and applies
the caller's output budget. Unused supplied entries remain validated but absent.
The API establishes no custody, qualification, capture match or consumer authority.

On 2026-10-14, Elixir 1.20.2 / Erlang OTP 29.0.4 ran
`mix pkg wotex-profiles check --no-retry`: all 15 configured checks passed,
80 tests at 95.7% coverage (unchanged 95% floor), zero Dialyzer warnings/skips.
Compiler, format, Credo, Doctor, documentation, locked/unused dependencies, both
audits, boundary, passive loading, archive and whitespace checks passed.

The compiler suite compares the returned reference array's digest with the
independently frozen closure vector, checks unused-data exclusion, missing
references and selected limits. Two fresh industrial/research archive consumers
pass five cases each, including the public references seam. No routine dependency,
catalogue fetch, host process or device qualification is introduced.

| Exact artifact | SHA-256 |
| --- | --- |
| Core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Runtime archive | `7c5412ea01dab311357a09276030ca005470c9bd8b0f471e0da3fb8ec5e4b1b4` |
| Profiles archive | `34a3dcef363a0b072fa2b260efeff8633f8365fd4aecfd1fbbc2c268c82e0b96` |
| Both consumer locks | `b54ba2c3f013c54417dbed832ff43071f55f265ed2d98cb9ec3f2079b8e31ff2` |

Consumers can now compare exact custody subjects using this public boundary,
without duplicating the compiler's closure traversal. Their current selected
source/artifacts and admission checks remain their own responsibility.
