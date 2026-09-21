# Wotex Modbus usage rules

These rules describe the completed WMB.01–WMB.08 contract. The package
catalogue records implementation status separately.

- Open the owned Modbus TCP connection with an explicit numeric host, port,
  unit identifier and finite deadline. Do not share its socket outside the
  package.
- Use only functions 1, 2, 3, 4, 5, 6, 15 and 16 through validated commands.
  Specify zero-based offset, quantity or values and keep the command's unit
  identifier authoritative.
- Serialize exchanges through the owned connection so MBAP transaction
  identifiers and responses remain correlated and bounded.
- Specify scalar kind, register width, byte order and word order for conversion;
  raw registers contain no semantic type information.
- Never automatically retry a write. A timeout may leave effect unknown, and a
  protocol acknowledgement does not prove physical state.
- Authentication, encryption, polling, Modbus RTU and application device policy
  are outside the final WMB contract.
