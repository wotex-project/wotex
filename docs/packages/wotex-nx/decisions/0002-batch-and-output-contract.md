# Decision 0002: heterogeneous feature batches and inert output

## Decision

A schema may contain features with different fixed shapes and dtypes. Therefore
each batch entry is a nested Nx container rather than one coerced matrix:

```text
{values_tuple, masks_tuple, quality_vector}
```

The tuple positions are the accepted schema order. Each value tensor retains
its declared dtype and shape. Its mask has the same shape and uses `u8`, where
one means observed and zero means filled by the feature's missing policy. This
matches the validity-mask convention of Axon and `Nx.Batch.pad/2`: a zero
padded row reads as unobserved. The quality vector uses the stable codes
exposed by `Wotex.Nx.quality_codes/0`, where zero means good, so padded rows
must be read through the mask rather than the quality vector.

Axis 0 of the stacked batch is the window row (time step) of one sample, not
an independent sample. `Nx.Serving` splits along axis 0 at `batch_size`; a
consumer hands a whole window to a serving or reduces per row explicitly.

Decoder output is one inert typed value. An Action proposal names an Action and
input but carries no callback, grant, credential, execution state, or policy
decision.

## Consequences

- Heterogeneous W3C DataSchemas are not silently coerced.
- Feature order and mask meaning are inspectable and testable.
- Consumers can change model frameworks without changing Thing semantics.
- Output cannot bypass consumer authorization or state admission.
