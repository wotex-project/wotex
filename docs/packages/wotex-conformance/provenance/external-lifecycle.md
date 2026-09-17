# External target lifecycle evidence

`Wotex.Conformance.Target.External` opens one Erlang Port for each explicit
invocation. A monotonic deadline covers request encoding, process startup,
non-suspending request submission, and response collection. The port closes on
every return path, and messages already delivered by that port are removed from
the caller mailbox.

The lifecycle tests exercise concurrent requests with distinct vector IDs,
targets that do not read standard input, continuous oversized output, partial
output followed by exit or delay, malformed output, mismatched vector identity,
and non-zero exit. They also verify that unrelated caller messages remain in the
mailbox. Runner tests change a verified subject archive before execution and
confirm that digest verification rejects it before the target writes its marker.

Run the focused evidence with:

```console
mix test test/wotex/conformance/external_lifecycle_test.exs \
  test/wotex/conformance/runner_test.exs
```

These checks establish bounded cooperative cleanup for the tested Erlang/OTP
runtime. They do not establish hard-real-time deadlines, descendant-process
termination, operating-system isolation, or safe execution of an untrusted
executable. The consumer supplies those controls.
