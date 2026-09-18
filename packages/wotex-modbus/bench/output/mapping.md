# Form mapping and in-process exchange

`Wotex.Modbus.Mapping.command/4` over three Forms of the draft Modbus
profile: a 64-coil `readproperty`, a `readproperty` of an `xsd:float`
holding-register pair with an unknown extension term, and a
`writeproperty` of an `xsd:double` in four registers with swapped word
order. Mapping validates the Form, the operation, the `modbus+tcp`
endpoint and one-based address, and encodes typed input.
`Wotex.Modbus.Mapping.decode/2` converts the raw result. The combined job
adds `Wotex.Modbus.Codec` request encoding and response parsing, which is
the in-process work of one Runtime interaction without the socket.


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



__Input: read 64 coils__

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
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap; text-align: right">73069.41 K</td>
    <td style="white-space: nowrap; text-align: right">0.0137 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5686.69%</td>
    <td style="white-space: nowrap; text-align: right">0.0125 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.0209 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap; text-align: right">41.72 K</td>
    <td style="white-space: nowrap; text-align: right">23.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.29%</td>
    <td style="white-space: nowrap; text-align: right">22.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">46.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap; text-align: right">40.01 K</td>
    <td style="white-space: nowrap; text-align: right">25.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.37%</td>
    <td style="white-space: nowrap; text-align: right">23.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">39.21 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap;text-align: right">73069.41 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap; text-align: right">41.72 K</td>
    <td style="white-space: nowrap; text-align: right">1751.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap; text-align: right">40.01 K</td>
    <td style="white-space: nowrap; text-align: right">1826.49x</td>
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
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap">0.0234 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap">38.30 KB</td>
    <td>1634.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap">41.07 KB</td>
    <td>1752.33x</td>
  </tr>
</table>



__Input: read float32 holding registers__

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
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap; text-align: right">8047.32 K</td>
    <td style="white-space: nowrap; text-align: right">0.124 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2418.29%</td>
    <td style="white-space: nowrap; text-align: right">0.125 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap; text-align: right">36.39 K</td>
    <td style="white-space: nowrap; text-align: right">27.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.26%</td>
    <td style="white-space: nowrap; text-align: right">25.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">41.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap; text-align: right">36.28 K</td>
    <td style="white-space: nowrap; text-align: right">27.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.96%</td>
    <td style="white-space: nowrap; text-align: right">26 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">44.08 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap;text-align: right">8047.32 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap; text-align: right">36.39 K</td>
    <td style="white-space: nowrap; text-align: right">221.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap; text-align: right">36.28 K</td>
    <td style="white-space: nowrap; text-align: right">221.81x</td>
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
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap">0.32 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap">44.77 KB</td>
    <td>139.78x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap">47.14 KB</td>
    <td>147.17x</td>
  </tr>
</table>



__Input: write float64 with swapped words__

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
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap; text-align: right">127886.75 K</td>
    <td style="white-space: nowrap; text-align: right">0.00782 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;61.10%</td>
    <td style="white-space: nowrap; text-align: right">0.00750 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.0121 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap; text-align: right">37.49 K</td>
    <td style="white-space: nowrap; text-align: right">26.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.11%</td>
    <td style="white-space: nowrap; text-align: right">25.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">39.71 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap; text-align: right">37.16 K</td>
    <td style="white-space: nowrap; text-align: right">26.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.45%</td>
    <td style="white-space: nowrap; text-align: right">25.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">39.79 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap;text-align: right">127886.75 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap; text-align: right">37.49 K</td>
    <td style="white-space: nowrap; text-align: right">3411.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap; text-align: right">37.16 K</td>
    <td style="white-space: nowrap; text-align: right">3441.46x</td>
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
    <td style="white-space: nowrap">convert mapped result</td>
    <td style="white-space: nowrap">0 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map Form to command</td>
    <td style="white-space: nowrap">43.40 KB</td>
    <td>&mdash;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map, encode, parse and convert</td>
    <td style="white-space: nowrap">44.93 KB</td>
    <td>&mdash;</td>
  </tr>
</table>