# Security

Report vulnerabilities privately to hello@wotex.io. Include affected versions,
reproduction steps, impact, and suggested mitigations when available.

Treat observations and metadata as untrusted input. Enforce consumer-selected
limits before forming windows or tensors. Never place secrets in observations,
provenance, errors, model outputs, or Action proposals. Numerical output remains
inert until a consumer performs its own authorization and admission.
