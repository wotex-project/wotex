# Wotex UDP

Wotex UDP 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.18 through
Elixir 1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).

Wotex UDP provides bounded datagram transport owned by a consumer process.
It is not a Web of Things binding. It does not parse payloads, discover
interfaces, resolve names, correlate requests, or retry traffic.

## Use

```elixir
alias Wotex.UDP
alias Wotex.UDP.{Config, Endpoint}

{:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
{:ok, config} = Config.new(local: local, max_datagram_bytes: 1_472)
{:ok, socket} = UDP.open(config)

try do
  {:ok, destination} = UDP.local(socket)
  :ok = UDP.send(socket, destination, <<1, 2, 3>>, 100)
  {:ok, datagram} = UDP.recv(socket, 100)
  {datagram.source, datagram.data}
after
  UDP.close(socket)
end
```

The caller owns socket cleanup and any process supervision. Constructing
values does not open sockets. A successful send means the local OS accepted
the datagram; it does not prove delivery or a remote effect.

Broadcast and multicast start disabled. Explicitly mark those destinations
with `Endpoint.broadcast/2` or `Endpoint.multicast/2` and opt in through
`Wotex.UDP.Config.new/1`. Multicast group membership requires a chosen IPv4 interface
address or IPv6 interface index.

Defaults cap datagrams at 1,472 bytes, request a 65,536-byte kernel receive
buffer, cap a batch at 32 datagrams, admit 32 concurrent owner operations and
65,536 queued send bytes, and cap each operation deadline at 60,000
milliseconds. Calls above the admission limits return `:overload` before
publishing a request. Expired queued sends are discarded before socket
I/O. The owner monitors admitted callers and cancels abandoned socket waits.
Complete requests and budgets publish atomically into an owner-owned queue;
a ten-millisecond sweep recovers a missed wakeup. Zero-timeout calls poll only
when no request is pending, with a handoff allowance of at most 100 milliseconds
capped by `max_timeout_ms`. Socket readiness is never awaited for such a poll.
An admitted close fences new producers and cancels pending work before releasing
the socket; it shares the call budget and can return `:overload`. `handle/1`
obtains a local owner's opaque handle without adding a mailbox request.
Unicast starts with a hop limit of 64; multicast starts with 1.
Enabling multicast also requires `multicast_interface:`: a concrete IPv4
interface address or a positive IPv6 interface index. The backend sets this
egress option before binding and fails open if the OS refuses it. Membership
calls separately name their receive interface; wildcard addresses, index zero
and conflicting IPv6 scopes are refused. Changing egress requires reopening
the owner with a new configuration.
The OS may adjust the receive buffer size. Oversize datagrams
are discarded with a typed error. `recv_batch/3` has one total deadline.

See the [WUD.01 contract](../../docs/packages/wotex-udp/specs/WUD.01-datagram-transport.md)
and its [catalogue](../../docs/packages/wotex-udp/specs/catalogue.yaml) for
implementation status and remaining evidence.

## Measurements

`mix bench --package wotex-udp` records pure constructor and complete
loopback send/receive measurements. The checked-in
[loopback results](bench/output/loopback.md) and
[constructor results](bench/output/datagram.md) describe earlier source inputs.
Current asynchronous owner costs remain unmeasured. These local software
measurements cannot establish network throughput or remote delivery.
