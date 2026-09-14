# Release evidence boundary

The package requirement is Elixir `~> 1.18`. Local compatibility evidence uses
separate build and dependency roots for these runtime cohorts:

| Lane | Elixir | Erlang/OTP | Required evidence |
| --- | --- | --- | --- |
| minimum | 1.18.4 | 27.3.4.15 | locked dependency resolution, warnings-as-errors compilation, formatting, and behavioral tests |
| current | 1.20.4 | 29.0.4 | the minimum lane plus documentation, coverage, static analysis, dependency audits, boundary review, package inspection, archive consumer execution, and the reference corpus |

The production dependency boundary contains `ex_json_schema` and `jason`, with
`decimal` as their shared transitive dependency in the resolved archive
consumer. Development and test tools do not run when the package loads. The
ignored local tracker records the exact source commit, lock digest, resolved
archive-consumer lock digest, tool versions, commands, and exit codes.

The candidate evidence identifies these immutable standard inputs:

| Input | SHA-256 |
| --- | --- |
| bundled TD 1.1 informative schema | `87481cfafa3847d0c593c047750e090d4365dcc0f1b5daab3a725d63c991a4da` |
| bundled Thing Model 1.1 informative schema | `3c8dedb2a534d089fdbd7fda8eb05a5b13237a2331f42e2af08cdb4a7af9fc7a` |
| Thing Description reference corpus 1.1.0 | `b1f9c259c24c7edf9faf8979204bf3105efcdf49e9b3dc69330c9475c4903154` |
| Thing Model reference corpus 1.1.0 | `800bfc2ea61f6c14167898e64bcdb8c8aff0a1fe9857505ed65f2837d6bd10a5` |

The archive carries Apache-2.0 package licensing, the W3C Software and Document
License notice, both bundled schemas, their modification record, and the WTX
specifications. Loading the archive defines no application callback and starts
no process.

Package version 0.1.0 remains a development API. WTX.03 version 1.2.0 classifies
malformed-option refusal as a pre-release admission correction. The public
contract is the documented operations, values, result shapes, stable error
matching fields, media types, and schema provenance. Evidence tests exercise
those behaviors without asserting a complete export set or struct layout.

The compatibility lanes do not cover every Elixir and Erlang/OTP combination,
another operating system or architecture, future dependency resolution, or a
published package. Passing release-readiness checks does not authorize a tag,
push, publication, or repository-visibility change.
