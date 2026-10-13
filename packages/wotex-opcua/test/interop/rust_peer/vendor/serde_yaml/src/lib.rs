//! Fixture-only compatibility names for the maintained YAML Serde API.
//!
//! This is first-party re-export code, not the deprecated upstream
//! serde_yaml implementation. The locked yaml_serde archive owns parsing.

pub use yaml_serde::*;

#[cfg(test)]
mod tests {
    use serde::{Deserialize, Serialize};

    #[derive(Debug, PartialEq, Serialize, Deserialize)]
    struct Configuration {
        endpoint: String,
        limits: Vec<u32>,
        enabled: bool,
    }

    #[test]
    fn structured_configuration_retains_values() {
        let yaml = "endpoint: opc.tcp://127.0.0.1:4840\nlimits: [1, 32]\nenabled: true\n";
        let config: Configuration = super::from_str(yaml).unwrap();
        assert_eq!(config.limits, vec![1, 32]);
        assert!(config.enabled);
        let value: super::Value = super::from_str(yaml).unwrap();
        let from_value: Configuration = super::from_value(value).unwrap();
        assert_eq!(config, from_value);
        let encoded = super::to_string(&config).unwrap();
        assert_eq!(super::from_str::<Configuration>(&encoded).unwrap(), config);
    }

    #[test]
    fn malformed_and_mistyped_configuration_is_refused() {
        for yaml in [
            "endpoint: [",
            "endpoint: x\nlimits: [wrong]\nenabled: true\n",
        ] {
            assert!(super::from_str::<Configuration>(yaml).is_err());
        }
    }
}
