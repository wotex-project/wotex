# Subscription notification round trip

Data-change notifications on one persistent Session against the same-stack open62541 peer, with the credentials, peer pacing and executables of the Persistent Session services benchmark. The subscription has one Value MonitoredItem on the peer's Double Variable `burst` with sampling interval 0, so the peer samples every write, and queue size 10. One measurement asks the peer to write five consecutive values in one server iteration and waits until the subscribing process has received the five notifications in order and without overflow. The peer's SDK revises the requested 10 ms publishing interval to its default minimum of 100 ms, so the wait for the next publishing cycle dominates this time; the delivery-latency table at the end isolates the path from the server's PublishTime to the subscriber.

## System

Benchmark suite executing on the following system:

<table style="width: 1%">
  <tr>
    <th style="width: 1%; white-space: nowrap">Operating System</th>
    <td>macOS</td>
  </tr><tr>
    <th style="white-space: nowrap">CPU Information</th>
    <td style="white-space: nowrap">Apple M5 Pro</td>
  </tr><tr>
    <th style="white-space: nowrap">Number of Available Cores</th>
    <td style="white-space: nowrap">18</td>
  </tr><tr>
    <th style="white-space: nowrap">Available Memory</th>
    <td style="white-space: nowrap">48 GB</td>
  </tr><tr>
    <th style="white-space: nowrap">Elixir Version</th>
    <td style="white-space: nowrap">1.20.2</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">29.0.4</td>
  </tr>
</table>

## Configuration

Benchmark suite executing with the following configuration:

<table style="width: 1%">
  <tr>
    <th style="width: 1%">:time</th>
    <td style="white-space: nowrap">5 s</td>
  </tr><tr>
    <th>:parallel</th>
    <td style="white-space: nowrap">1</td>
  </tr><tr>
    <th>:warmup</th>
    <td style="white-space: nowrap">1 s</td>
  </tr>
</table>

## Statistics



Run Time

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Deviation</th>
    <th style="text-align: right">Median</th>
    <th style="text-align: right">99th&nbsp;%</th>
  </tr>

  <tr>
    <td style="white-space: nowrap">Five data changes to five delivered notifications</td>
    <td style="white-space: nowrap; text-align: right">10.00</td>
    <td style="white-space: nowrap; text-align: right">99.98 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.77%</td>
    <td style="white-space: nowrap; text-align: right">100.33 ms</td>
    <td style="white-space: nowrap; text-align: right">100.84 ms</td>
  </tr>

</table>

## Notification delivery latency

Every notification the job received, measured with the host's realtime clock,
which the peer shares: from the PublishTime of the server's NotificationMessage
to receipt by the subscribing process, which covers the server's encoding and
message security, the loopback connection, the SDK's decoding, the native
host's sequence check and value projection, custody, the BEAM host's frame
validation and delivery; and from the value's source timestamp, taken when the
peer wrote it, to receipt, which adds the wait for the next publishing cycle.

| Interval | Notifications | Minimum | Median | Mean | 99th percentile | Maximum |
| :-- | --: | --: | --: | --: | --: | --: |
| PublishTime to receipt | 310 | 187 µs | 989 µs | 832 µs | 1.60 ms | 1.64 ms |
| Source timestamp to receipt | 310 | 97.03 ms | 100.19 ms | 99.83 ms | 100.82 ms | 100.86 ms |
