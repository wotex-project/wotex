# Wotex Nx usage rules

These rules describe the completed WNX.01 and WNX-C contract. The package
catalogue records implementation status separately.

- Build observations with explicit Thing identity, Interaction Affordance,
  timestamp, unit, quality and value metadata. Admit only the documented core
  DataSchema numerical subset.
- Define ordered features, shapes, dtype, missing-value policy, normalization,
  temporal window and work limits explicitly. Never infer feature order or
  silently coerce invalid, missing, non-finite or overflowing values.
- Use only an explicit unit-conversion callback and revalidate its result. A
  callback supplies conversion, not authority or lifecycle ownership.
- Preserve deterministic selection, row order, mask polarity (`1` means
  observed), quality codes and lazy `Nx.Batch` layout across encoding.
- Decode model output only through an explicit output schema into inert
  Observation, Prediction, Anomaly or ActionProposal values.
- Keep clocks, model selection, training, serving, persistence, policy and
  Action dispatch outside the package.
