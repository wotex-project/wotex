# Datagram value construction

Pure IPv4 and IPv6 endpoint and finite configuration construction.

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



__Input: ipv4__

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
    <td style="white-space: nowrap">construct local endpoint and finite config</td>
    <td style="white-space: nowrap; text-align: right">4.31 M</td>
    <td style="white-space: nowrap; text-align: right">231.76 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2597.07%</td>
    <td style="white-space: nowrap; text-align: right">208 ns</td>
    <td style="white-space: nowrap; text-align: right">334 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">construct local endpoint and finite config</td>
    <td style="white-space: nowrap;text-align: right">4.31 M</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">construct local endpoint and finite config</td>
    <td style="white-space: nowrap">672 B</td>
    <td>&nbsp;</td>
  </tr>
</table>



__Input: ipv6__

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
    <td style="white-space: nowrap">construct local endpoint and finite config</td>
    <td style="white-space: nowrap; text-align: right">4.12 M</td>
    <td style="white-space: nowrap; text-align: right">242.77 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1802.75%</td>
    <td style="white-space: nowrap; text-align: right">208 ns</td>
    <td style="white-space: nowrap; text-align: right">334 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">construct local endpoint and finite config</td>
    <td style="white-space: nowrap;text-align: right">4.12 M</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">construct local endpoint and finite config</td>
    <td style="white-space: nowrap">800 B</td>
    <td>&nbsp;</td>
  </tr>
</table>