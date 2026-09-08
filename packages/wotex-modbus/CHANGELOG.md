# Changelog

## 0.1.0-dev

- Remove the obsolete Decimal advisory waiver while retaining the exact lock
  and bounded parser regression.
- Reject unknown, duplicate and unsupported-security connection/Runtime options.
- Establish the consumer-neutral library contract and full package gates.
- Implement eight Modbus TCP functions, bounded framing, response correlation,
  explicit connection ownership, finite deadlines and structured failures.
- Add register conversion, draft Form mapping and the Runtime transport.
- Prove software interoperability against pinned libmodbus source.

- Define the target software contract and ordered implementation packages with
  pinned sources, explicit APIs/limits and required software acceptance vectors.
