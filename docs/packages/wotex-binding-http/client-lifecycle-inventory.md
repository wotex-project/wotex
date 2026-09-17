# Client and SSE lifecycle evidence inventory

This `WBH-C02` inventory binds every package-owned client and Server-Sent
Events lifecycle cell to named executable vectors for package baseline
`wotex_binding_http 0.1.0`. Callback failure values are untrusted: the binding
normalizes them without reflecting reasons, and validation failures after a
handle is returned trigger one best-effort cleanup call.

| Cell | Reviewed contract | Named vectors |
| --- | --- | --- |
| WBH-L01 | `request/3` success plus error, malformed return, raise, exit, throw, and redaction | WBH-L01-P, WBH-L01-N1, WBH-L01-N2 |
| WBH-L02 | `subscribe/4` success plus error, malformed return, raise, exit, and throw | WBH-L02-P, WBH-L02-N1, WBH-L02-N2 |
| WBH-L03 | `close/2` success plus error, malformed return, raise, exit, throw, argument validation, and absent stop credential | WBH-L03-P, WBH-L03-N1, WBH-L03-N2 |
| WBH-L04 | Invalid status, media type, body, revalidated response, or response value after a returned handle causes cleanup | WBH-L04-N1, WBH-L04-N2, WBH-L04-N3 |
| WBH-L05 | Cleanup error, malformed return, raise, exit, or throw does not replace the primary handshake error | WBH-L05-N |
| WBH-L06 | Two valid direct transport closes remain two explicit client calls; the package has no global deduplication state | WBH-L06-P |
| WBH-L07 | Runtime serializes concurrent logical stops so exactly one reaches `close/2` | WBH-L07-P |
| WBH-L08 | A newly constructed configuration with equal client options cannot close a handle opened by another configuration instance | WBH-L08-N |
| WBH-L09 | Receiver death makes Runtime close the stream and terminate its subscription owner | WBH-L09-P |
| WBH-L10 | A linked client connection loss becomes `transport_down`, close, and Runtime owner termination | WBH-L10-P |
| WBH-L11 | Loading, constructing, and executing the binding defines no application callback and starts no package-owned process; the supplied Runtime owner is passed through unchanged | WBH-L11-P, WBH-L11-N |

The vector names appear in `transport_test.exs`, `integration_test.exs`,
`library_contract_test.exs`, and `client_lifecycle_inventory_test.exs` under
`test/wotex/binding/http/`. The inventory test keeps this table and those names
in sync and dynamically checks the no-package-owner path.

## Pending establishment belongs to the supplied client

`subscribe/4` executes in the supplied Runtime owner, but opening a socket and
creating any connection process are client actions. A client must arrange
monitoring before an in-progress connection can outlive that owner, then abort
or close the connection if the owner exits before `subscribe/4` returns. While
the callback is pending, the binding has received neither a connection nor an
opaque handle, so it cannot perform or promise that cleanup.

The package vectors prove that the exact owner is passed to the callback and
that the binding creates no substitute owner. They do not prove an arbitrary
client's pending-open cancellation, socket release, reconnect behavior, or
exactly-once remote close. Those require evidence from the selected client and
consumer Runtime supervision policy.
