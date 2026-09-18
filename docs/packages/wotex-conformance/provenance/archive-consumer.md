# Archive-only consumer evidence

Work item WCF-C03 is exercised by `bin/check_archive.exs`. The checker verifies
and unpacks the current Hex archive, copies the declared `jason` dependency into
its temporary workspace, and compiles every packaged library source with
warnings as errors. It then starts a fresh Elixir virtual machine from that
workspace. The only non-runtime code paths supplied to that virtual machine are
the isolated dependency bytecode and bytecode compiled from the unpacked
archive; its code path contains no entry under the source checkout.

The minimal consumer in `test/fixtures/archive_consumer.exs` loads the packaged
Thing Description 1.1 corpus and verifies the synthetic subject archive before
each target run. The separately copied
`test/fixtures/external_target.exs` fixture derives observations only from the
target request. It neither loads a subject package nor reads vector expectations
or provenance. One selected vector exercises these runner classifications:

| Target behavior | Result status | Result code |
| --- | --- | --- |
| normalized observed value equal to the expectation | `pass` | `exact_match` |
| normalized observed value different from the expectation | `fail` | `exact_mismatch` |
| unsupported operation | `unsupported` | `operation_not_implemented` |
| response after the configured deadline | `infrastructure_error` | `target_timeout` |
| malformed response bytes | `infrastructure_error` | `invalid_target_json` |

Run the proof with the repository's selected Elixir and Erlang/OTP versions
(the root `mise.toml`) from `packages/wotex-conformance`:

```console
mix run --no-start bin/check_archive.exs
```

From the repository root the same command is
`mix pkg wotex-conformance run --no-start bin/check_archive.exs`; the full
package gate runs it as well.

The command builds one exact archive into an OS-temporary directory and prints
the verified corpus coordinates and SHA-256 digest of the archive it
exercised. Its temporary archive, dependency copy,
bytecode, consumer, target, and subject are removed after the run. The proof
opens no network connection and uses no tested subject dependency.

This fixture proves the package archive, external-target protocol, runner-side
comparison, and five distinct WCF-C03 outcomes under the recorded runtime. Its
synthetic structural rules are not a Thing Description validator. The result
does not establish third-party interoperability, complete Thing Description
1.1 conformance, operating-system isolation, runtime-cohort compatibility,
certification, or release stability.
