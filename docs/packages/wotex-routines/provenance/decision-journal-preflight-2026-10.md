# Journal decision oracle preflight

Recorded: 2026-10-16. Scope: local native preflight before archive extraction.
Source parent: `e1b46588`. The complete byte identities below bind the new
journal sources before their owning commit. The
[accepted archive profile](../decisions/verified-decision-archive-profile.md)
still requires both extracted consumers, identity checks and semantic mutations.

| File | SHA-256 of complete bytes |
| --- | --- |
| `packages/wotex-routines/test/support/archive/decision_inputs.exs` | `290d1492e7ab82e599badbe44d764e629f2bf021fa1b2ee68b0c4fe2a3629109` |
| `packages/wotex-routines/test/support/archive/decision_journal_oracle.exs` | `132d1caa08b8a35037e1fb881e5026fab8ed03aa23775165fd818113bb5a5f70` |
| `packages/wotex-routines/test/support/archive/decision_journal_consumer.exs` | `6ea2c462acc390bcaec1c1838d89bcea5754d2908f01c59a7d155e782c1a2cb2` |

Executed from the repository root through `mise exec --` on Elixir 1.20.2 and
OTP 29.0.4, with the existing package lock and explicit WOTEX_PATH_DEPS=1:

```text
mix pkg wotex-routines format test/support/archive/decision_journal_oracle.exs test/support/archive/decision_journal_consumer.exs
WOTEX_ROUTINES_COMPILER_BASIS=sha256:7777777777777777777777777777777777777777777777777777777777777777 mix pkg wotex-routines test test/support/archive/decision_journal_consumer.exs
mix pkg wotex-routines credo --strict --files-included test/support/archive/decision_journal_oracle.exs --files-included test/support/archive/decision_journal_consumer.exs
```

All seven journal cases pass in 31.8 seconds with no skipped/excluded cases.
Strict Credo finds no issues across 136 source files. The explicit synthetic
compiler basis is a preflight input, not an archive hash, release identity or
consumer dependency selection. No extracted archive was used.

## Independent expected records

The shared DecisionArchiveInputs supplies raw synthetic declarations and public
claim preparation. DecisionConsumerJournal independently owns explicit scripted
rows, original identities, complete receipts, pending state and full collection
hashing. It neither walks compiled execution trees nor imports the source-family
oracle, native decision reference or private production verification helpers.
Public canonical JSON and SHA-256 supply representation identities only.

The journal also owns revision-bound captures, known-original history and held
charges. Inert publication compares the entire claim with the expected scripted
relation, rejects stale captures and known history presented as new, and prevents
lost charges. Serialization/restoration retains history and charges while
discarding outstanding captures. Time-only publication delay preserves the
latched point, but current effects still require a fresh complete input/time cut.
This is a finite test consumer, not a persistence implementation or host contract.

Its separate arbitration oracle indexes resource domains by full operation keys
from its own expected pending records. It checks constraints, selected/suppressed
overrides, all incompatible live operations and complete contributor decisions
before choosing groups. It does not call production arbitration to compute an
expected result or reuse the source family's all-pairs algorithm.

The seven cases cover the accepted finite profile:

- VDA-T1: complete scripted initial relations under both Time grammars for noop,
  effect, sequence/delay, wait, parallel, fixed/unknown branch and invoked child
  conditions; retained delay motion preserves its original start. Basis and
  plausible motion forgeries refuse.
- VDA-T2: held/duplicate/handoff/failure/unknown/satisfaction and cancellation
  retain complete receipts and spend. Restored terminal history cannot repeat
  charge or handoff. A coherent refund passes representation construction but
  fails point verification and the consumer's independent charge guard. Late
  effect evidence cannot hide expiry or enable its dependent path; an invoked
  child's earlier deadline also stops continuation.
- VDA-T3: independent complete Edge@1/@2 baseline, rising report, replacement
  and unqualified state records; a shape-valid false baseline refuses.
- VDA-T4: negative delay, wait, Fact and UTC-window contributors bound the whole
  current cut. Authenticated inert publication after latency retains its original
  start; the fresh complete cut reaches that boundary and sees the conflict.
  Rehashed missing membership and narrowed/widened cells refuse.
- VDA-T5: full proposed/reserved records, retained contributors and twelve
  policy/batch combinations. The complete 64-member/1,024-pending trace has 32
  conflicted contributors, sixteen selected groups and 736 deferred contributors.
  A separately compiled 1,023 profile refuses the aggregate. Pending/state and
  arbitration-decision omissions refuse.
- VDA-T6: both relevant UTC endpoint directions, generation/presence changes,
  elapsed basis/grammar/regression, exact non-time input and irrelevant UTC
  replacement/loss. Point and checked Times remain explicit, and historical
  transitions are unchanged.
- VDA-T7: malformed/forged native wrappers, omitted fields, extra authority
  labels, unsupported Collection@1 and frozen complete-pending Model scope
  refuse. All four Decision APIs accept exact aggregate byte bounds and refuse
  one-under selections. Each selected Limits value has a freshly compiled
  Program; constructor measurement also counts the complete output.

## Limits and cleanup

The two native preflights do not establish extracted dependency identity or
semantic mutation catches. The opt-in runner, both eight-case archive projects,
twelve isolated mutation runs, complete VD-T1–T14 matrix and owning package
milestone remain open. Current consumer adoption, installed clocks/source
custody, wider Model/Analysis support and physical authority remain separate.

These tests create no Docker resources, archive, disposable filesystem workspace
or generated documentation. Helper modules and the scripted journal live only
in the test VM. Reusable locked dependency/build/PLT caches are retained. No
release, dependency pin, remote ref or repository visibility changed.
