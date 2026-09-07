# Changelog

## 0.1.0

- Invert mask polarity to `1 = observed`, `0 = filled`, matching
  `Nx.Batch.pad/2` and Axon validity masks; document the batch axis as the
  window row of one sample and the `Nx.Serving` split consequence.
- Reject rows naming a feature absent from the schema (`unknown_row_feature`).
- Check non-finite conversions on host values before tensor allocation; build
  constant masks once per feature; round anomaly thresholds without a tensor.
- Add `Encoded.schema/1`, `timestamps/1`, `provenance/1`, `layout/1`,
  `row_count/1`, `template/1` and an `Nx.LazyContainer` implementation.
- Select window observations by binary search over sorted groups.
- Select latest window observations in a linear pass per row without sorting
  eligible candidates; preserve exact selection, age bounds and ID ties.

- Establish typed observation, deterministic window, tensor, mask, batch, and
  inert numerical-output conversion contracts.
