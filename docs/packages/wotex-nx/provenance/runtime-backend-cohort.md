# Runtime and backend compatibility cohort

Manifest `WNX-COHORT-01`, revision `1.1.0`, defines the executable reference
cohort for WNX.01. It is a stable verification input, not a mutable execution
receipt. Consumers keep run logs, commit-bound results, and orchestration state
outside this repository. Revision 1.1.0 declares the cohort as the two
repository CI lanes on which every package gate runs: the minimum lane
(Elixir 1.18.4-otp-27, Erlang/OTP 27.3.4.15) and the current lane (Elixir
1.20.2-otp-29, Erlang/OTP 29.0.4, the root `mise.toml` pin). The archive
consumer accepts either lane and prints which one ran; the Nx release,
backend, compiler and comparison policy are unchanged.

| Dimension | Declared reference value |
| --- | --- |
| Minimum lane | Elixir 1.18.4, Erlang/OTP 27.3.4.15 |
| Current lane | Elixir 1.20.2, Erlang/OTP 29.0.4 |
| Wotex | 0.1 archive contract |
| Wotex Nx | 0.1 archive contract |
| Nx | 0.13.1 |
| Backend | `Nx.BinaryBackend` |
| Defn compiler | `Nx.Defn.Evaluator` |
| Executable | `bin/check_archive.exs` against the exact Wotex Nx and core archives |

The package requirement remains Elixir `~> 1.18`. The exact values above name
the cohort for which the archive and independent-reference evidence is run;
they do not make every other compatible patch release incorrect, nor do they
claim equivalent bytes, floating-point behavior, performance, or device
semantics for another runtime, compiler, platform, Nx release, or backend.

## Comparison policy

Identity, feature order, shapes, masks, quality codes, timestamps, provenance,
integer values, boolean values, error codes, and inert-output fields are exact.
No tolerance applies to those values.

WNX.01 permits host-double arithmetic followed by rounding into the declared
floating dtype. The reference vector normalizes `0.1` with
`{:z_score, 0, 3}` and independently casts the mathematical result `0.1 / 3`
with Nx 0.13.1 on `Nx.BinaryBackend`. The stored value MUST exactly equal that
independently cast tensor. The following absolute bounds describe only the
permitted cast error for this vector; they are not general model tolerances:

| Dtype | Independently cast value | Maximum absolute error from `0.1 / 3` |
| --- | ---: | ---: |
| `bf16` | 0.033203125 | 0.00014 |
| `f16` | 0.0333251953125 | 0.00001 |
| `f32` | 0.03333333507180214 | 0.000000002 |
| `f64` | the host-double result | 0 |

Anomaly thresholds follow the same narrower-dtype rule and are compared only
after representation in the accepted dtype. No cross-backend byte identity,
train/serve bitwise equivalence, model accuracy, or backend performance claim
is made by this cohort.
