// SPDX-License-Identifier: Apache-2.0
// Independent WMB.09 reference; no WoTEx decoder, device or host package code.
use base64::{engine::general_purpose::STANDARD, Engine};
use serde::de::{DeserializeSeed, Error, MapAccess, Visitor};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::cell::Cell;
use std::fmt;
use std::io::{Read, Write};

const SAFE: i64 = 9_007_199_254_740_991;
const CONTRACT: &str = "0ca3f57f25c41ca3d04f8b0d97d5ffc780d90440d4d482cb9dbf743e45437e42";
type Result<T> = std::result::Result<T, ()>;

struct Seed<'a> {
    depth: usize,
    nodes: &'a Cell<usize>,
}

impl<'de> DeserializeSeed<'de> for Seed<'_> {
    type Value = Value;
    fn deserialize<D: serde::Deserializer<'de>>(
        self,
        deserializer: D,
    ) -> std::result::Result<Value, D::Error> {
        if self.depth > 24 || self.nodes.get() == 4096 {
            return Err(D::Error::custom("protocol"));
        }
        self.nodes.set(self.nodes.get() + 1);
        deserializer.deserialize_any(self)
    }
}

impl<'de> Visitor<'de> for Seed<'_> {
    type Value = Value;
    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("bounded protocol value")
    }
    fn visit_bool<E: Error>(self, value: bool) -> std::result::Result<Value, E> {
        Ok(Value::Bool(value))
    }
    fn visit_unit<E: Error>(self) -> std::result::Result<Value, E> {
        Ok(Value::Null)
    }
    fn visit_i64<E: Error>(self, value: i64) -> std::result::Result<Value, E> {
        if (-SAFE..=SAFE).contains(&value) {
            Ok(value.into())
        } else {
            Err(E::custom("protocol"))
        }
    }
    fn visit_u64<E: Error>(self, value: u64) -> std::result::Result<Value, E> {
        if value <= SAFE as u64 {
            Ok(value.into())
        } else {
            Err(E::custom("protocol"))
        }
    }
    fn visit_f64<E: Error>(self, value: f64) -> std::result::Result<Value, E> {
        // The lexical pass already excludes fractions/exponents. serde_json
        // represents the legal integer token -0 as a float; normalize it here.
        if value == 0.0 {
            Ok(0.into())
        } else {
            Err(E::custom("protocol"))
        }
    }
    fn visit_str<E: Error>(self, value: &str) -> std::result::Result<Value, E> {
        if value.len() <= 87_384 {
            Ok(Value::String(value.to_owned()))
        } else {
            Err(E::custom("protocol"))
        }
    }
    fn visit_string<E: Error>(self, value: String) -> std::result::Result<Value, E> {
        if value.len() <= 87_384 {
            Ok(Value::String(value))
        } else {
            Err(E::custom("protocol"))
        }
    }
    fn visit_map<A: MapAccess<'de>>(self, mut access: A) -> std::result::Result<Value, A::Error> {
        let mut fields = Map::new();
        while let Some(key) = access.next_key::<String>()? {
            if fields.len() == 256 || key.len() > 87_384 || fields.contains_key(&key) {
                return Err(A::Error::custom("protocol"));
            }
            let value = access.next_value_seed(Seed {
                depth: self.depth + 1,
                nodes: self.nodes,
            })?;
            fields.insert(key, value);
        }
        Ok(Value::Object(fields))
    }
    // No inbound v1 frame field admits an array.
}

fn parse(bytes: &[u8]) -> Result<Value> {
    if bytes.is_empty() || bytes.len() >= 131_072 || bytes.starts_with(&[0xef, 0xbb, 0xbf]) {
        return Err(());
    }
    let mut quoted = false;
    let mut escaped = false;
    let mut position = 0;
    while position < bytes.len() {
        let byte = bytes[position];
        if byte == b'\r' || byte == b'\n' {
            return Err(());
        }
        if quoted {
            if escaped {
                escaped = false;
            } else if byte == b'\\' {
                escaped = true;
            } else if byte == b'"' {
                quoted = false;
            }
        } else if byte == b'"' {
            quoted = true;
        } else if byte.is_ascii_digit() || byte == b'-' {
            let start = position;
            position += 1;
            while position < bytes.len()
                && (bytes[position].is_ascii_digit() || b".eE+-".contains(&bytes[position]))
            {
                position += 1;
            }
            if position - start > 18 || !bytes[start + 1..position].iter().all(u8::is_ascii_digit) {
                return Err(());
            }
            continue;
        }
        position += 1;
    }
    let text = std::str::from_utf8(bytes).map_err(|_| ())?;
    let mut deserializer = serde_json::Deserializer::from_str(text);
    let nodes = Cell::new(0);
    let value = Seed {
        depth: 1,
        nodes: &nodes,
    }
    .deserialize(&mut deserializer)
    .map_err(|_| ())?;
    deserializer.end().map_err(|_| ())?;
    Ok(value)
}

fn closed(value: &Value, keys: &[&str]) -> bool {
    value
        .as_object()
        .is_some_and(|map| map.len() == keys.len() && keys.iter().all(|key| map.contains_key(*key)))
}
fn integer(value: &Value, low: i64, high: i64) -> bool {
    value
        .as_i64()
        .is_some_and(|number| (low..=high).contains(&number))
}
fn text(value: &Value, low: usize, high: usize) -> bool {
    value
        .as_str()
        .is_some_and(|string| (low..=high).contains(&string.len()))
}
fn digest(value: &Value) -> bool {
    value.as_str().is_some_and(|string| {
        string.len() == 64
            && string
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    })
}
fn token(value: &Value) -> bool {
    let alpha = |byte: u8| byte.is_ascii_lowercase() || byte.is_ascii_digit();
    value.as_str().is_some_and(|string| {
        (1..=128).contains(&string.len())
            && alpha(string.as_bytes()[0])
            && string
                .bytes()
                .all(|byte| alpha(byte) || b"._:/-".contains(&byte))
    })
}
fn flat(value: &Value) -> bool {
    value.as_object().is_some_and(|map| {
        map.len() <= 16
            && map.iter().all(|(key, item)| {
                (1..=128).contains(&key.len())
                    && (item.is_null()
                        || item.is_boolean()
                        || integer(item, -SAFE, SAFE)
                        || text(item, 0, 256))
            })
            && serde_json::to_vec(value).is_ok_and(|bytes| bytes.len() <= 4096)
    })
}

fn hash(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

struct Configuration {
    width: usize,
    reverse_bytes: bool,
    reverse_words: bool,
    signed: bool,
    scale: i32,
}
impl Configuration {
    fn new(value: &Value) -> Result<Self> {
        if !closed(
            value,
            &["registers", "byte_order", "word_order", "scale", "signed"],
        ) || !integer(&value["registers"], 1, 4)
            || !integer(&value["scale"], -32768, 32767)
        {
            return Err(());
        }
        let order = |item: &Value| -> Result<bool> {
            match item.as_str() {
                Some("big") => Ok(false),
                Some("little") => Ok(true),
                _ => Err(()),
            }
        };
        Ok(Self {
            width: value["registers"].as_u64().ok_or(())? as usize,
            reverse_bytes: order(&value["byte_order"])?,
            reverse_words: order(&value["word_order"])?,
            signed: value["signed"].as_bool().ok_or(())?,
            scale: value["scale"].as_i64().ok_or(())? as i32,
        })
    }
    fn project(&self, bytes: &[u8], metadata: &Value) -> std::result::Result<Value, &'static str> {
        if !closed(metadata, &["format"]) || !metadata["format"].is_string() {
            return Err("invalid_input");
        }
        if metadata["format"] != "packed-bcd-v1" {
            return Err("unsupported_format");
        }
        if bytes.len() != self.width * 2 {
            return Err("invalid_input");
        }
        let mut words: Vec<Vec<u8>> = bytes
            .chunks_exact(2)
            .map(|word| {
                let mut word = word.to_vec();
                if self.reverse_bytes {
                    word.reverse();
                }
                word
            })
            .collect();
        if self.reverse_words {
            words.reverse();
        }
        let mut digits: String = words
            .iter()
            .flatten()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        let negative = if self.signed {
            match digits.pop() {
                Some('c') => false,
                Some('d') => true,
                _ => return Err("invalid_input"),
            }
        } else {
            false
        };
        if !digits.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err("invalid_input");
        }
        if digits.bytes().all(|byte| byte == b'0') {
            return if negative {
                Err("unsupported_value")
            } else {
                Ok(json!({"type": "decimal", "coefficient": "0", "exponent": 0}))
            };
        }
        let unscaled = digits.trim_end_matches('0');
        let exponent = self.scale + (digits.len() - unscaled.len()) as i32;
        if exponent > 32767 {
            return Err("unsupported_value");
        }
        let coefficient = unscaled.trim_start_matches('0');
        let coefficient = if negative {
            format!("-{coefficient}")
        } else {
            coefficient.to_owned()
        };
        Ok(json!({"type": "decimal", "coefficient": coefficient, "exponent": exponent}))
    }
}

fn decode_bytes(value: &Value) -> Result<Vec<u8>> {
    if !closed(value, &["type", "base64"])
        || value["type"] != "bytes"
        || !text(&value["base64"], 0, 87_384)
    {
        return Err(());
    }
    let encoded = value["base64"].as_str().ok_or(())?;
    let padding = encoded
        .bytes()
        .rev()
        .take_while(|byte| *byte == b'=')
        .count();
    if encoded.len() % 4 != 0
        || padding > 2
        || encoded.len() / 4 * 3 < padding
        || encoded.len() / 4 * 3 - padding > 65_536
    {
        return Err(());
    }
    let bytes = STANDARD.decode(encoded).map_err(|_| ())?;
    if STANDARD.encode(&bytes) != encoded {
        return Err(());
    }
    Ok(bytes)
}

struct Codec {
    configuration: Option<Configuration>,
    next: i64,
    decode_ms: i64,
}
impl Codec {
    fn accept<W: Write>(&mut self, frame: Value, output: &mut W) -> Result<bool> {
        if !integer(&frame["v"], 1, 1) {
            return Err(());
        }
        if frame["type"] == "stop" {
            return if closed(&frame, &["v", "type"]) {
                Ok(false)
            } else {
                Err(())
            };
        }
        let response = if let Some(configuration) = &self.configuration {
            if frame["type"] != "decode"
                || !closed(
                    &frame,
                    &[
                        "v",
                        "type",
                        "seq",
                        "request_id",
                        "budget_ms",
                        "bytes",
                        "metadata",
                    ],
                )
                || !integer(&frame["seq"], 1, SAFE)
                || frame["seq"] != self.next
                || !text(&frame["request_id"], 1, 256)
                || !integer(&frame["budget_ms"], 1, self.decode_ms)
                || !flat(&frame["metadata"])
            {
                return Err(());
            }
            let bytes = decode_bytes(&frame["bytes"])?;
            let mut response = json!({"v": 1, "seq": self.next, "request_id": frame["request_id"]});
            match configuration.project(&bytes, &frame["metadata"]) {
                Ok(value) => {
                    response["type"] = "result".into();
                    response["value"] = value;
                }
                Err(code) => {
                    response["type"] = "refusal".into();
                    response["code"] = code.into();
                }
            }
            self.next += 1;
            response
        } else {
            if frame["type"] != "hello"
                || !closed(
                    &frame,
                    &[
                        "v",
                        "type",
                        "instance_id",
                        "generation",
                        "descriptor_sha256",
                        "contract_id",
                        "contract_sha256",
                        "decode_ms",
                        "configuration",
                        "configuration_sha256",
                    ],
                )
                || !token(&frame["instance_id"])
                || !integer(&frame["generation"], 1, SAFE)
                || !digest(&frame["descriptor_sha256"])
                || frame["contract_id"] != "wotex.modbus.register-decimal"
                || frame["contract_sha256"] != CONTRACT
                || !integer(&frame["decode_ms"], 1, 1000)
                || !digest(&frame["configuration_sha256"])
            {
                return Err(());
            }
            let configuration = Configuration::new(&frame["configuration"])?;
            let canonical = serde_json::to_vec(&frame["configuration"]).map_err(|_| ())?;
            if hash(&canonical) != frame["configuration_sha256"] {
                return Err(());
            }
            self.decode_ms = frame["decode_ms"].as_i64().ok_or(())?;
            self.configuration = Some(configuration);
            let mut response = frame;
            response.as_object_mut().ok_or(())?.remove("configuration");
            response["type"] = "ready".into();
            response
        };
        let bytes = serde_json::to_vec(&response).map_err(|_| ())?;
        output.write_all(&bytes).map_err(|_| ())?;
        output.write_all(b"\n").map_err(|_| ())?;
        output.flush().map_err(|_| ())?;
        Ok(true)
    }
}

fn run() -> Result<()> {
    for (input, expected) in [
        (
            "",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
        (
            "abc",
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        ),
        (
            "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
        ),
    ] {
        if hash(input.as_bytes()) != expected {
            return Err(());
        }
    }
    let mut input = std::io::stdin().lock();
    let mut output = std::io::stdout().lock();
    let mut codec = Codec {
        configuration: None,
        next: 1,
        decode_ms: 0,
    };
    let mut chunk = [0_u8; 4096];
    let mut pending = Vec::new();
    loop {
        let count = match input.read(&mut chunk) {
            Ok(count) => count,
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return Err(()),
        };
        if count == 0 {
            return if pending.is_empty() { Ok(()) } else { Err(()) };
        }
        for byte in &chunk[..count] {
            if *byte == b'\n' {
                if !codec.accept(parse(&pending)?, &mut output)? {
                    return Ok(());
                }
                pending.clear();
            } else {
                if pending.len() == 131_071 {
                    return Err(());
                }
                pending.push(*byte);
            }
        }
    }
}

fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    if !matches!(std::panic::catch_unwind(run), Ok(Ok(()))) {
        std::process::exit(65);
    }
}
