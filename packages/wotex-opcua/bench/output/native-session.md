# Persistent Session services

End-to-end services through the public API of the package on one persistent Session of `Wotex.OPCUA.Open62541` (Basic256Sha256, SignAndEncrypt, anonymous user) with the executables of the native build, against the same-stack open62541 peer the build also produces (`priv/native/paged_peer.c`) on loopback, with disposable RSA 2048 credentials the script generates. Every call crosses the BEAM host, the custody guardian, the native owner, the SDK, the secure channel and the peer. The jobs are a Read of an Int32 Value; a Write of a Double, which the peer rejects with BadUserAccessDenied because its Variables grant anonymous users no write access, so it covers the whole request path without storing a value; one Browse page (the peer returns one reference per page) and the release of its continuation point; a Browse of three children in three pages (Browse and two BrowseNext); and the creation and deletion of a subscription with one Value MonitoredItem. Between iterations the peer waits up to 20 ms on its standard input, and each request would wait for that timeout; the script keeps one statistics request in flight on that input, so the peer's loop turns continuously. Each job runs in a process that opened its own Session; one measurement is one call.

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
    <td style="white-space: nowrap">Read of an Int32 Value</td>
    <td style="white-space: nowrap; text-align: right">376.64</td>
    <td style="white-space: nowrap; text-align: right">2.66 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.99%</td>
    <td style="white-space: nowrap; text-align: right">2.66 ms</td>
    <td style="white-space: nowrap; text-align: right">2.71 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Write of a Double, rejected with BadUserAccessDenied</td>
    <td style="white-space: nowrap; text-align: right">363.47</td>
    <td style="white-space: nowrap; text-align: right">2.75 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.89%</td>
    <td style="white-space: nowrap; text-align: right">2.75 ms</td>
    <td style="white-space: nowrap; text-align: right">3.01 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Browse page of one reference and release of its continuation</td>
    <td style="white-space: nowrap; text-align: right">187.40</td>
    <td style="white-space: nowrap; text-align: right">5.34 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.80%</td>
    <td style="white-space: nowrap; text-align: right">5.35 ms</td>
    <td style="white-space: nowrap; text-align: right">5.40 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Subscribe and unsubscribe a Value MonitoredItem</td>
    <td style="white-space: nowrap; text-align: right">126.01</td>
    <td style="white-space: nowrap; text-align: right">7.94 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.36%</td>
    <td style="white-space: nowrap; text-align: right">7.91 ms</td>
    <td style="white-space: nowrap; text-align: right">8.22 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Browse of three children in three pages</td>
    <td style="white-space: nowrap; text-align: right">124.05</td>
    <td style="white-space: nowrap; text-align: right">8.06 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.70%</td>
    <td style="white-space: nowrap; text-align: right">8.07 ms</td>
    <td style="white-space: nowrap; text-align: right">8.20 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Read of an Int32 Value</td>
    <td style="white-space: nowrap;text-align: right">376.64</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Write of a Double, rejected with BadUserAccessDenied</td>
    <td style="white-space: nowrap; text-align: right">363.47</td>
    <td style="white-space: nowrap; text-align: right">1.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Browse page of one reference and release of its continuation</td>
    <td style="white-space: nowrap; text-align: right">187.40</td>
    <td style="white-space: nowrap; text-align: right">2.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Subscribe and unsubscribe a Value MonitoredItem</td>
    <td style="white-space: nowrap; text-align: right">126.01</td>
    <td style="white-space: nowrap; text-align: right">2.99x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Browse of three children in three pages</td>
    <td style="white-space: nowrap; text-align: right">124.05</td>
    <td style="white-space: nowrap; text-align: right">3.04x</td>
  </tr>

</table>