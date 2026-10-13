# Fixture YAML compatibility

This first-party crate replaces the deprecated registry `serde_yaml` package
in the disposable OPC UA software peer. Its compatibility version satisfies
the peer's existing dependency requirement; it re-exports the maintained
[YAML Serde](https://github.com/yaml/yaml-serde) 0.10.7 API. No upstream
serde_yaml or unsafe-libyaml implementation is copied here. The selected
registry source and checksums belong to the peer's Cargo lock.

This crate is fixture support, not a production protocol dependency. The two
configuration tests check typed/value round trips and malformed input refusal.
