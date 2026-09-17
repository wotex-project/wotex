# Reference corpus evidence

Wotex evaluates its Thing Description and Thing Model value boundaries against
two content-addressed corpora derived from the W3C Web of Things Thing
Description 1.1 Recommendation dated 5 December 2023.

| Corpus | Revision | Vectors | Digest |
| --- | --- | ---: | --- |
| `w3c.wot.thing-description.1.1.baseline` | 1.1.0 | 16 | `sha256:b1f9c259c24c7edf9faf8979204bf3105efcdf49e9b3dc69330c9475c4903154` |
| `w3c.wot.thing-model.1.1.baseline` | 1.1.0 | 8 | `sha256:800bfc2ea61f6c14167898e64bcdb8c8aff0a1fe9857505ed65f2837d6bd10a5` |

The corpora cover the `thing_description.parse`,
`thing_description.validate`, `thing_model.parse`, and
`thing_model.validate` operations. Positive vectors project required metadata,
Interaction Affordances, Forms, DataSchemas, security definitions, multilingual
metadata, extension terms, Thing Model placeholders, references, and model
versions. Counterexamples cover context order, required members, security
references, Thing Model type, and instance-version metadata.

`bin/wcf_target.exs` adapts those operations to the WCF target protocol 1.0.
For parse operations it encodes the declared document and calls the aggregate
parser. For validate operations it calls native-map construction. It projects
the resulting document by the declared RFC 6901 JSON Pointers and reduces
errors to the stable code, phase, and path fields. The adapter derives each
observation from the operation and declared input. It does not receive an
expectation and does not branch on vector identity.

The evidence lane compiles Wotex from the exact unpacked Hex archive, invokes
the adapter as a fresh external process for every vector, and records the
archive, corpus, report, runtime, and dependency digests in the ignored local
tracker.

This evidence covers the listed value operations and vectors. It does not
establish complete Recommendation conformance, compatibility with a second
Thing Description implementation, a protocol binding, a WoT Profile,
certification, or a published package.
