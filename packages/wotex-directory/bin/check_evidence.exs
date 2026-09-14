Code.require_file("evidence.exs", __DIR__)
DirectoryEvidence.finish!(System.fetch_env!("WOTEX_EVIDENCE_ROOT"))
