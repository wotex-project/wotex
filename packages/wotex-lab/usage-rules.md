# Wotex Lab usage rules

These rules describe the completed WLB.01–WLB.12 and WLB-C01–WLB-C14 contract.
The package catalogue records implementation status separately.

- Treat `Wotex.Lab` as a consumer laboratory, not a protocol implementation,
  production framework, identity provider or unrestricted agent platform.
- Start isolated Lab instances and components explicitly. Admit closed scenario
  descriptors before startup, bound runner and replay work, and clean up every
  partially started or cancelled run.
- Use reference Runtime, HTTP, MQTT, Directory, Continuum and Nx adapters only
  through sibling public APIs. Optional integrations may be absent and must
  return structured unavailable errors.
- Keep Nx, Axon, Explorer and formal-verification results inert. A prediction,
  proposal, proof or counterexample never grants Action authority.
- Record evidence against exact artifacts, inputs, containment profile,
  environment and outcome. A scenario declaration or source-only test is not
  evidence that an external target ran or an upstream package is complete.
- Start metrics history, GreptimeDB access, AI inspection, Workbench and Nerves
  hosts explicitly with bounded inputs and outputs. No database, listener, LLM
  call, model download or public host starts from dependency loading.
- Keep documentation, graph, cookbook and machine-interface outputs
  allowlisted, consumer-neutral and free of credentials or mutable execution
  state.
