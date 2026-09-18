# GATT attribute value conversion

`Wotex.BLE.Value.encode/3` and `Wotex.BLE.Value.decode/3` for a signed
16-bit integer, an IEEE 754 double and 512 bytes of UTF-8 text (the
attribute value limit), with the default little-endian and with big-endian
byte order. Integer codecs check the range, floating-point codecs the exact
width, and text is checked as valid UTF-8; byte order does not apply to
text.


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



__Input: UTF-8 text, 512 bytes__

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
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap; text-align: right">1.10 M</td>
    <td style="white-space: nowrap; text-align: right">911.62 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;41.67%</td>
    <td style="white-space: nowrap; text-align: right">875 ns</td>
    <td style="white-space: nowrap; text-align: right">1167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">1.08 M</td>
    <td style="white-space: nowrap; text-align: right">923.81 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;64.62%</td>
    <td style="white-space: nowrap; text-align: right">875 ns</td>
    <td style="white-space: nowrap; text-align: right">1167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap; text-align: right">1.08 M</td>
    <td style="white-space: nowrap; text-align: right">924.47 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;576.35%</td>
    <td style="white-space: nowrap; text-align: right">875 ns</td>
    <td style="white-space: nowrap; text-align: right">1125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap; text-align: right">1.07 M</td>
    <td style="white-space: nowrap; text-align: right">932.20 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;480.73%</td>
    <td style="white-space: nowrap; text-align: right">875 ns</td>
    <td style="white-space: nowrap; text-align: right">1166 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap;text-align: right">1.10 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">1.08 M</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap; text-align: right">1.08 M</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap; text-align: right">1.07 M</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
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
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap">64 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap">128 B</td>
    <td>2.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap">88 B</td>
    <td>1.38x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap">104 B</td>
    <td>1.63x</td>
  </tr>
</table>



__Input: float64, 8 bytes__

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
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap; text-align: right">24.77 M</td>
    <td style="white-space: nowrap; text-align: right">40.36 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10881.76%</td>
    <td style="white-space: nowrap; text-align: right">41 ns</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">21.69 M</td>
    <td style="white-space: nowrap; text-align: right">46.10 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8204.92%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap; text-align: right">12.17 M</td>
    <td style="white-space: nowrap; text-align: right">82.16 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6596.44%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap; text-align: right">11.08 M</td>
    <td style="white-space: nowrap; text-align: right">90.23 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4871.59%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap;text-align: right">24.77 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">21.69 M</td>
    <td style="white-space: nowrap; text-align: right">1.14x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap; text-align: right">12.17 M</td>
    <td style="white-space: nowrap; text-align: right">2.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap; text-align: right">11.08 M</td>
    <td style="white-space: nowrap; text-align: right">2.24x</td>
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
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap">72 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap">120 B</td>
    <td>1.67x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap">328 B</td>
    <td>4.56x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap">376 B</td>
    <td>5.22x</td>
  </tr>
</table>



__Input: int16, 2 bytes__

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
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">25.80 M</td>
    <td style="white-space: nowrap; text-align: right">38.75 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9788.92%</td>
    <td style="white-space: nowrap; text-align: right">41 ns</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap; text-align: right">25.03 M</td>
    <td style="white-space: nowrap; text-align: right">39.95 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8478.72%</td>
    <td style="white-space: nowrap; text-align: right">41 ns</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap; text-align: right">22.08 M</td>
    <td style="white-space: nowrap; text-align: right">45.28 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9951.34%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap; text-align: right">14.97 M</td>
    <td style="white-space: nowrap; text-align: right">66.78 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6600.11%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap;text-align: right">25.80 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap; text-align: right">25.03 M</td>
    <td style="white-space: nowrap; text-align: right">1.03x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap; text-align: right">22.08 M</td>
    <td style="white-space: nowrap; text-align: right">1.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap; text-align: right">14.97 M</td>
    <td style="white-space: nowrap; text-align: right">1.72x</td>
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
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap">48 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode little-endian</td>
    <td style="white-space: nowrap">24 B</td>
    <td>0.5x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode big-endian</td>
    <td style="white-space: nowrap">72 B</td>
    <td>1.5x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode little-endian</td>
    <td style="white-space: nowrap">136 B</td>
    <td>2.83x</td>
  </tr>
</table>