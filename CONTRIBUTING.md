# Contributing

Contributions must preserve the storage-neutral boundary and use exact W3C Web
of Things terminology. Begin behavior changes with a normative specification or
an accepted issue that identifies the affected requirement and evidence vector.

Run `mix check` before proposing a change. A standards claim must identify the
exact revision, operation, assumptions, fixture digest, and result. Unsupported
cells remain absent rather than documented as planned support.

Do not add a database, application callback, hidden process, consumer-specific
namespace, credential store, transport connection, or physical-state authority.
