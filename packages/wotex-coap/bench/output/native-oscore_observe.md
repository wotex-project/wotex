# Protected Observe notifications through the native helper

One native OSCORE observation (`Wotex.CoAP.subscribe/2`, the helper `wotex.coap.native.build` built, under custody) of a dynamic resource on libcoap 4.3.5's `coap-server` on loopback, built and started as for the unary benchmark. Each iteration changes the resource with an unprotected UDP PUT from a second session and waits until the subscription's receiver holds the protected notification carrying the new 16-byte or 512-byte value: the PUT exchange, the peer's notification, its OSCORE verification and freshness check in the helper, report credit and the relay to the receiver.

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
    <td style="white-space: nowrap">change and notify, 16-byte value</td>
    <td style="white-space: nowrap; text-align: right">1.39 K</td>
    <td style="white-space: nowrap; text-align: right">0.72 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.15%</td>
    <td style="white-space: nowrap; text-align: right">0.74 ms</td>
    <td style="white-space: nowrap; text-align: right">1.12 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">change and notify, 512-byte value</td>
    <td style="white-space: nowrap; text-align: right">0.81 K</td>
    <td style="white-space: nowrap; text-align: right">1.24 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.14%</td>
    <td style="white-space: nowrap; text-align: right">1.26 ms</td>
    <td style="white-space: nowrap; text-align: right">1.40 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">change and notify, 16-byte value</td>
    <td style="white-space: nowrap;text-align: right">1.39 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">change and notify, 512-byte value</td>
    <td style="white-space: nowrap; text-align: right">0.81 K</td>
    <td style="white-space: nowrap; text-align: right">1.72x</td>
  </tr>

</table>