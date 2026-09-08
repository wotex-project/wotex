# Modbus executable evidence

Verified 2026-09-08 with Elixir 1.20.2 / OTP 29.0.4. `WOTEX_PATH_DEPS=1 mix check`
passes compilation, formatting, Credo, Dialyzer, dependency audits, Doctor,
coverage, docs, archive inspection and application-callback absence.
The supported Elixir 1.18+ lower-version matrix has not been executed here.
The pinned Decimal parser regression remains active without advisory waivers.
The explicit interoperability suite passed against libmodbus v3.1.12 commit
`9af6c16074df566551bca0a7c37443e48f216289` in the repository container fixture.
All eight advertised functions and remote exceptions have asserted responses.
This evidence covers software peers, not physical equipment or certification.

| Test source | SHA-256 |
| --- | --- |
| `test/interop/modbus_test.exs` | `1ce2829ea172ae0eae6377d20522797e1cec561b37e1cd55f52ce272110384a4` |
| `test/wotex/modbus/codec_test.exs` | `7407a96dbd3a86fd0bb1e961095541d2152692431b52d299b758e9333d8b4dd4` |
| `test/wotex/modbus/connection_test.exs` | `61deffb801f1586095a0ad17716da3b1b602189a832ef93261893fc0af7d2ae7` |
| `test/wotex/modbus/contract_test.exs` | `c967cb1432a1682b8990c8a496da98b2e0d402a9a23fce88f461f99ea13b7f80` |
| `test/wotex/modbus/dependency_security_test.exs` | `aed05db96411eaf7a8fbc030092387a556abbd9c7e7cdaef8ddfd145b91b91c3` |
| `test/wotex/modbus/mapping_test.exs` | `1173c9c2ff25c66d5b6a96c37c38541b62d7f0bb37f301817cbd5d147545cc2a` |
| `test/wotex/modbus/value_test.exs` | `a94472085e36bd1c03f0b53e585e660182ff15d2e43024fb95bfce9b1a63fe3b` |

Follow-up wire-boundary regression: forged Command structs are revalidated before
encoding. Invalid function, value, quantity and offset cannot silently wrap into
an ADU. This change is covered by the codec test and the full local gate.
