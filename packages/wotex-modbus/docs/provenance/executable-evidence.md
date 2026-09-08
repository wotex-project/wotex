# Modbus executable evidence

Verified 2026-09-08 with Elixir 1.20.2 / OTP 29.0.4. `WOTEX_PATH_DEPS=1 mix check`
passes compilation, formatting, Credo, Dialyzer, dependency audits, Doctor,
coverage, docs, archive inspection and application-callback absence.
The explicit interoperability suite passed against libmodbus v3.1.12 commit
`9af6c16074df566551bca0a7c37443e48f216289` in the repository container fixture.
All eight advertised functions and remote exceptions have asserted responses.
This evidence covers software peers, not physical equipment or certification.

| Executable vectors | SHA-256 |
| --- | --- |
| `test/wotex/modbus/codec_test.exs` | `0f604caa50c35deadfcc9faa5e8d75e2f95d3531d860e028a16b2873933520dc` |
| `test/wotex/modbus/connection_test.exs` | `aa753fbeebab05655bd82676cf7df1702d03817fcdf710efad7ee457d66fad8f` |
| `test/wotex/modbus/contract_test.exs` | `c967cb1432a1682b8990c8a496da98b2e0d402a9a23fce88f461f99ea13b7f80` |
| `test/wotex/modbus/dependency_security_test.exs` | `e2ffb876b5aafc63caa04c7536745bfc96dd85ff4f4878f37502143aa1da56a9` |
| `test/wotex/modbus/mapping_test.exs` | `d1a9d6e65bcef64c9540a04beec0166a12bee176bf7c410075fca5e6f5509f3b` |
| `test/wotex/modbus/value_test.exs` | `a94472085e36bd1c03f0b53e585e660182ff15d2e43024fb95bfce9b1a63fe3b` |
| `test/interop/modbus_test.exs` | `1ce2829ea172ae0eae6377d20522797e1cec561b37e1cd55f52ce272110384a4` |
