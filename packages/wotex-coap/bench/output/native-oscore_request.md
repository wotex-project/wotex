# Protected unary requests through the native helper

`Wotex.CoAP.get/3` and `Wotex.CoAP.put/4` on one native OSCORE session (the helper `wotex.coap.native.build` built, under custody) against libcoap 4.3.5's `coap-server` on loopback, built as the software lane builds its same-stack peer (the workspace's verified archive and the lane's CMake options) and started with the lane's OSCORE context and arguments, but warnings-only logging: GETs of 64-byte and 512-byte representations and a PUT of a 512-byte body, each request and response one datagram. Each call returns after the helper has relayed the complete, verified response to the session.

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
    <td style="white-space: nowrap">GET, 64-byte representation</td>
    <td style="white-space: nowrap; text-align: right">1.96 K</td>
    <td style="white-space: nowrap; text-align: right">509.27 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.80%</td>
    <td style="white-space: nowrap; text-align: right">503.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">658.52 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">GET, 512-byte representation</td>
    <td style="white-space: nowrap; text-align: right">1.89 K</td>
    <td style="white-space: nowrap; text-align: right">528.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.70%</td>
    <td style="white-space: nowrap; text-align: right">522.90 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">679.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">PUT, 512-byte body</td>
    <td style="white-space: nowrap; text-align: right">1.45 K</td>
    <td style="white-space: nowrap; text-align: right">689.52 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.60%</td>
    <td style="white-space: nowrap; text-align: right">684.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">844.15 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">GET, 64-byte representation</td>
    <td style="white-space: nowrap;text-align: right">1.96 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">GET, 512-byte representation</td>
    <td style="white-space: nowrap; text-align: right">1.89 K</td>
    <td style="white-space: nowrap; text-align: right">1.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">PUT, 512-byte body</td>
    <td style="white-space: nowrap; text-align: right">1.45 K</td>
    <td style="white-space: nowrap; text-align: right">1.35x</td>
  </tr>

</table>