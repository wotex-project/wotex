# Wotex Conformance usage rules

These rules describe the completed WCF.01 and WCF-C contract. The package
catalogue records implementation status separately.

- Load only digest-verified corpora and construct Subject, Claim, Vector,
  Target and Environment values through their closed public boundaries.
- Keep expectations, expected digests, vector identity and provenance on the
  runner side. Send only the declared input to the target.
- Run an external target by direct executable invocation with literal
  arguments, a scrubbed environment, deadlines and output limits; never use a
  shell. The consumer supplies operating-system containment for descendants.
- Distinguish `pass`, `fail`, `unsupported`, `not_run` and
  `infrastructure_error` outcomes. Invalid runner configuration is an error,
  not a fabricated report.
- Bind every report to the exact subject archive, corpus, claim, vector,
  protocol, environment and observation digests without retaining raw target
  output or credentials.
- Treat a passing report as evidence only for its recorded scope. It is not
  certification or proof of general W3C Web of Things conformance.
