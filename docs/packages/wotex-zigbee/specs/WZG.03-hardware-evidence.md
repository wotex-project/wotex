# WZG.03 Hardware and evidence

## Status

Accepted target evidence contract for a planned package.

The first hardware lane MUST record:
- host OS/runtime;
- coordinator model/chipset/revision;
- coordinator firmware version and digest;
- serial/NCP protocol revision;
- channel/network parameters;
- joined device exact manufacturer/model/endpoints/clusters;
- restart/rejoin behavior;
- malformed/truncated host frames;
- USB disconnect/reconnect;
- coordinator restart;
- network backup/restore;
- WAN-disconnected operation.

A safety sensor requires additional application-level qualification; successful Zigbee pairing alone is not safety evidence.

Changing coordinator chipset or firmware is a new evidence cohort.

The first macOS lane SHOULD pair the purchased Aqara Smoke Detector through an operator-controlled coordinator, but Aqara-specific semantics remain outside this package.
