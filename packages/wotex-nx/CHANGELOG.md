# Changelog

## 0.1.0

- WNX.01 v1.2.0 documents and tests the existing selection-work admission score,
  including empty/singleton inputs and exact budget thresholds. Selection,
  tensor/mask semantics and accepted budgets are unchanged. Workspace checks
  require a locked dependency resolution; malformed-constructor tests exercise
  dynamic calls without generating intentional static type warnings.

- Retain exact Decimal 3.1.1 lock and bounded parser regressions while removing
  the stale, unmatched advisory suppression; all advisory checks remain active.

- Invert mask polarity to `1 = observed`, `0 = filled`, matching
  `Nx.Batch.pad/2` and Axon validity masks; document the batch axis as the
  window row of one sample and the `Nx.Serving` split consequence.
- Reject rows naming a feature absent from the schema (`unknown_row_feature`).
- Check non-finite conversions on host values before tensor allocation; build
  constant masks once per feature; round anomaly thresholds without a tensor.
- Add `Encoded.schema/1`, `timestamps/1`, `provenance/1`, `layout/1`,
  `row_count/1`, `template/1` and an `Nx.LazyContainer` implementation.
- Select window observations by binary search over sorted groups.
- Add `to_map/1` read-only views to `Observation`, `Prediction`, `Anomaly` and
  `ActionProposal`.
- Select latest window observations in a linear pass per row without sorting
  eligible candidates; preserve exact selection, age bounds and ID ties.

- Establish typed observation, deterministic window, tensor, mask, batch, and
  inert numerical-output conversion contracts.
