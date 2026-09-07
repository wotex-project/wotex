%{
  ignore_paths: [~r(^test/support/), ~r(^lib/wotex/lab/options\.ex$)],
  exception_moduledoc: true,
  failed: true,
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_spec_coverage: 100,
  raise: false,
  reporter: Doctor.Reporters.Full
}
