# Basis vector provenance

The WRO.01 corpus in `priv/vectors/wro-01.json` is synthetic software data.
Scalar temperature, Boolean Event, fast Boolean actuator, slow fraction
actuator and finite media Action contracts are authored independently of any
consumer product or vendor protocol. Installed identity digests are fixture
identities; they do not authenticate an implementation or qualify a device.

Expected temperature values are calculated from Celsius plus 273.15 Kelvin
and Fahrenheit's 5/9 affine conversion: 25 C equals 298150 millikelvin, 0 C
273150, absolute zero 0, 32 F 273150 and 212 F 373150. 33 F is inexact in that
integer target unit. Fraction vectors use 1000000 ppm per whole and 100 percent
per whole. Electric potential remains incompatible with fraction.

The basis tests retain the full Continuum mapping, source/receipt generations,
replay and quality, reject missing closure and cycles, validate complete role
bindings, and prevent derived expiry crossing a contributor's receipt epoch.
The schema tests independently validate required/unknown fields and closed
constructs. Constructor hashes are compared with the corpus's independently
sorted JSON identities. These checks establish the pure foundation; they do
not execute the planned routine kernel, prove collection completeness, grant
an interaction or provide installed-host/physical evidence.
