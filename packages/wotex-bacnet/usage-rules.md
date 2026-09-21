# Wotex BACnet usage rules

These rules describe the completed WBA.01–WBA.06 contract. The package
catalogue records implementation status separately.

- Use the standalone facade for typed Property reads and writes, sequential
  batch reads, bounded Who-Is discovery and Change of Value subscriptions.
- Select the client explicitly. Use the owned `Wotex.BACnet.IPv4` stack when
  package-enforced ingress bounds are required; a borrowed BACstack client
  remains consumer-owned and must declare its receive and retry policy.
- Specify object, Property, array index, priority, route, timeout and write
  authority explicitly. Never automatically retry a timed-out write.
- Use the read/write Runtime profile for finite interactions and the IP COV
  profile only with a verified bounded ingress transport and supervised relay.
- Treat discovery as bounded observation. An I-Am result never replaces the
  configured route, authorizes communication or raises an APDU limit.
- BACnet/SC, MS/TP and BBMD routing are outside the final WBA contract. A wire
  acknowledgement is not canonical Property truth or proof of physical effect.
