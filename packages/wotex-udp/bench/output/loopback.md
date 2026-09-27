# UDP loopback datagrams

Complete send and receive through a caller-owned IPv4 loopback socket.

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



__Input: bytes_64__

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
    <td style="white-space: nowrap">send and receive a complete loopback datagram</td>
    <td style="white-space: nowrap; text-align: right">54.08 K</td>
    <td style="white-space: nowrap; text-align: right">18.49 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.81%</td>
    <td style="white-space: nowrap; text-align: right">18.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">24.75 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">send and receive a complete loopback datagram</td>
    <td style="white-space: nowrap;text-align: right">54.08 K</td>
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
    <td style="white-space: nowrap">send and receive a complete loopback datagram</td>
    <td style="white-space: nowrap">936 B</td>
    <td>&nbsp;</td>
  </tr>
</table>



__Input: bytes_1472__

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
    <td style="white-space: nowrap">send and receive a complete loopback datagram</td>
    <td style="white-space: nowrap; text-align: right">54.06 K</td>
    <td style="white-space: nowrap; text-align: right">18.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.91%</td>
    <td style="white-space: nowrap; text-align: right">18.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">24.71 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">send and receive a complete loopback datagram</td>
    <td style="white-space: nowrap;text-align: right">54.06 K</td>
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
    <td style="white-space: nowrap">send and receive a complete loopback datagram</td>
    <td style="white-space: nowrap">920 B</td>
    <td>&nbsp;</td>
  </tr>
</table>