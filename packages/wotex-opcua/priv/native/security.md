# Native credential preflight

`security.c` implements the pre-network credential subset of WOP-S03/X03.
The caller supplies validated open parameters and an explicit wall-clock sample.
The adapter repeats shape admission, copies at most 64 KiB per DER input and owns
all parsed objects until `wop_security_clear`. Failed admission releases every
acquisition; private-key copies are cleansed. It loads no default trust store,
file, OpenSSL configuration, dynamic provider, network resource or Python code.

Certificates and CRLs must parse completely and round-trip as DER. Application
and user private keys must be unencrypted PKCS#8, match their certificates and
pass RSA pairwise validation. PEM, encrypted containers, PKCS#1 keys and trailing
objects fail. RSA keys must have at least 2048 bits; certificate signatures use
SHA-256 or stronger accepted SHA-2/SHA-3 digests. Application leaves require
digital-signature, key-encipherment and data-encipherment usage, the appropriate
client/server EKU, and exactly one matching application URI. User certificates
require client authentication and digital-signature usage. Unknown noncritical
certificate extensions survive validation; unknown critical or duplicate
extensions fail. Client/user issuer trust is the server's responsibility; local
checks establish their identity, validity, usage and possession of the key.

Only one supplied, current, self-signed CA directly issuing the pinned server
leaf is accepted. The adapter checks root and leaf signatures and uses an
isolated OpenSSL verification store containing that root and the explicit CRL.
No intermediate or alternative chain is supplied. The complete issuer CRL must
have a current update interval, matching issuer and valid strong signature
(including RSA-PSS with an admitted digest);
revoked server serials fail. Delta/indirect CRLs and critical CRL extensions are
outside this profile. Validity starts are inclusive; expiry is exclusive.

The endpoint authority is checked without DNS resolution. IP literals match IP
SAN bytes; DNS names use exact SAN matching without wildcards or common-name
fallback. Application URIs match byte-for-byte. The reusable peer verifier checks
the complete DER pin and refreshes validity/revocation checks against caller
time. `session_config.c` installs it as the SDK connection callback, selects
the exact secure policy and token, preserves binary username passwords,
disables reconnect and rejects interactive private-key prompts. The caller
retains credentials until SDK config deletion.

`security_check.c` generates disposable RSA credentials entirely in C and tests
valid, invalid and boundary cases at an explicit supplied time. The real executable
also invokes preflight: shape-valid invalid DER returns `certificate_invalid`
in the opening phase, before any network call. Preflight success still returns
`unsupported_protocol` there. The separate `session_probe.c` activates a
Basic256Sha256 anonymous Session and reads the NamespaceArray against the
independent asyncua fixture. This is test evidence, not production P02/P03
acceptance or the full policy/token matrix.
