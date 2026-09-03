%{
  # These modules are cross-module implementation details, not public API.
  ignore_paths: [
    ~r(^test/support/),
    ~r(^lib/wotex_continuum/contract\.ex$),
    ~r(^lib/wotex_continuum/validation\.ex$)
  ],
  ignore_for_refs: [],
  exception_moduledoc: true,
  failed: true,
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 80,
  min_overall_doc_coverage: 100,
  min_overall_spec_coverage: 80,
  raise: false,
  reporter: Doctor.Reporters.Full
}
