# OPC UA Form mapping and Runtime transport requests

A Property read of a Double, a Property write of a Double declared by the
Form's `wotex:variantType`, and a Property write of an explicitly typed flat
array of 16 ByteStrings of 64 bytes, each selected from an `opc.tcp` Form
by `Wotex.Runtime.FormSelector` through the one-shot profile.
`Wotex.OPCUA.Mapping.command/4` parses the endpoint and NodeId and converts
write input to a typed Variant. The `request/3` callback of
`Wotex.OPCUA.Transport` adds the target check, deadline budget, session open
and close, the client call, DataValue or status projection and the Runtime
Result. The client is an in-process `Wotex.OPCUA.Client` answering from
prepared values; the failure job has it reject every request with
`:connection_failed`, which the transport classifies with
`Wotex.OPCUA.Error.classify/1` (unknown effect for writes).


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
    <td style="white-space: nowrap">3 s</td>
  </tr><tr>
    <th>:parallel</th>
    <td style="white-space: nowrap">1</td>
  </tr><tr>
    <th>:warmup</th>
    <td style="white-space: nowrap">1 s</td>
  </tr>
</table>

## Statistics



__Input: read Double__

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
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap; text-align: right">303.26 K</td>
    <td style="white-space: nowrap; text-align: right">3.30 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;316.24%</td>
    <td style="white-space: nowrap; text-align: right">2.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">7.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">251.25 K</td>
    <td style="white-space: nowrap; text-align: right">3.98 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;232.84%</td>
    <td style="white-space: nowrap; text-align: right">3.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">241.13 K</td>
    <td style="white-space: nowrap; text-align: right">4.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;189.22%</td>
    <td style="white-space: nowrap; text-align: right">3.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">9.63 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap;text-align: right">303.26 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">251.25 K</td>
    <td style="white-space: nowrap; text-align: right">1.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">241.13 K</td>
    <td style="white-space: nowrap; text-align: right">1.26x</td>
  </tr>

</table>



Memory Usage

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Factor</th>
  </tr>
  <tr>
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap">4.35 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap">5.38 KB</td>
    <td>1.24x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap">5.75 KB</td>
    <td>1.32x</td>
  </tr>
</table>



__Input: write ByteString array of 16 x 64 bytes__

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
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap; text-align: right">152.61 K</td>
    <td style="white-space: nowrap; text-align: right">6.55 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;87.62%</td>
    <td style="white-space: nowrap; text-align: right">5.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">40.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">142.46 K</td>
    <td style="white-space: nowrap; text-align: right">7.02 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;80.10%</td>
    <td style="white-space: nowrap; text-align: right">5.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">40.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">139.84 K</td>
    <td style="white-space: nowrap; text-align: right">7.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;79.11%</td>
    <td style="white-space: nowrap; text-align: right">5.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">41.29 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap;text-align: right">152.61 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">142.46 K</td>
    <td style="white-space: nowrap; text-align: right">1.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">139.84 K</td>
    <td style="white-space: nowrap; text-align: right">1.09x</td>
  </tr>

</table>



Memory Usage

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Factor</th>
  </tr>
  <tr>
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap">8.86 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap">9.80 KB</td>
    <td>1.11x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap">9.80 KB</td>
    <td>1.11x</td>
  </tr>
</table>



__Input: write Double__

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
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap; text-align: right">290.69 K</td>
    <td style="white-space: nowrap; text-align: right">3.44 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;285.53%</td>
    <td style="white-space: nowrap; text-align: right">2.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">7.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">256.38 K</td>
    <td style="white-space: nowrap; text-align: right">3.90 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;240.22%</td>
    <td style="white-space: nowrap; text-align: right">3.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">246.67 K</td>
    <td style="white-space: nowrap; text-align: right">4.05 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;201.83%</td>
    <td style="white-space: nowrap; text-align: right">3.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.83 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap;text-align: right">290.69 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">256.38 K</td>
    <td style="white-space: nowrap; text-align: right">1.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">246.67 K</td>
    <td style="white-space: nowrap; text-align: right">1.18x</td>
  </tr>

</table>



Memory Usage

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Factor</th>
  </tr>
  <tr>
    <td style="white-space: nowrap">map Form to OPC UA request</td>
    <td style="white-space: nowrap">4.62 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap">5.63 KB</td>
    <td>1.22x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap">5.46 KB</td>
    <td>1.18x</td>
  </tr>
</table>