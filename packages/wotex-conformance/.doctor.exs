%Doctor.Config{
  # Test fixtures and doubles are not part of the public library API.
  ignore_paths: [~r(^test/support/)],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 100
}
