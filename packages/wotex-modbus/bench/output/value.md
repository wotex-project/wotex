# Typed register value conversion

`Wotex.Modbus.Value.decode/3` and `Wotex.Modbus.Value.encode/3` for a
signed 16-bit integer, an IEEE 754 single-precision value in two registers
and a double-precision value in four registers, with the default big-endian
byte and word order and with both orders swapped. Each call validates the
order options and the exact register width.


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



__Input: float32, 2 registers__

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
    <td style="white-space: nowrap; text-align: right">29.64 M</td>
    <td style="white-space: nowrap; text-align: right">33.73 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2709.55%</td>
    <td style="white-space: nowrap; text-align: right">29.20 ns</td>
    <td style="white-space: nowrap; text-align: right">41.70 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">13.41 M</td>
    <td style="white-space: nowrap; text-align: right">74.60 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1491.46%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">11.48 M</td>
    <td style="white-space: nowrap; text-align: right">87.14 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5106.84%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">9.48 M</td>
    <td style="white-space: nowrap; text-align: right">105.50 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3674.30%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
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
    <td style="white-space: nowrap;text-align: right">29.64 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">13.41 M</td>
    <td style="white-space: nowrap; text-align: right">2.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">11.48 M</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">9.48 M</td>
    <td style="white-space: nowrap; text-align: right">3.13x</td>
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
    <td style="white-space: nowrap">168 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap">208 B</td>
    <td>1.24x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap">480 B</td>
    <td>2.86x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap">520 B</td>
    <td>3.1x</td>
  </tr>
</table>



__Input: float64, 4 registers__

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
    <td style="white-space: nowrap; text-align: right">28.06 M</td>
    <td style="white-space: nowrap; text-align: right">35.64 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2779.50%</td>
    <td style="white-space: nowrap; text-align: right">29.20 ns</td>
    <td style="white-space: nowrap; text-align: right">45.80 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">14.73 M</td>
    <td style="white-space: nowrap; text-align: right">67.87 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1175.37%</td>
    <td style="white-space: nowrap; text-align: right">58.40 ns</td>
    <td style="white-space: nowrap; text-align: right">95.80 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">9.07 M</td>
    <td style="white-space: nowrap; text-align: right">110.22 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4341.70%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">7.41 M</td>
    <td style="white-space: nowrap; text-align: right">135.02 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1050.78%</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
    <td style="white-space: nowrap; text-align: right">209 ns</td>
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
    <td style="white-space: nowrap;text-align: right">28.06 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">14.73 M</td>
    <td style="white-space: nowrap; text-align: right">1.9x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">9.07 M</td>
    <td style="white-space: nowrap; text-align: right">3.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">7.41 M</td>
    <td style="white-space: nowrap; text-align: right">3.79x</td>
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
    <td style="white-space: nowrap">200 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap">704 B</td>
    <td>3.52x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap">336 B</td>
    <td>1.68x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap">840 B</td>
    <td>4.2x</td>
  </tr>
</table>



__Input: int16, 1 register__

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
    <td style="white-space: nowrap; text-align: right">35.97 M</td>
    <td style="white-space: nowrap; text-align: right">27.80 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3155.88%</td>
    <td style="white-space: nowrap; text-align: right">25 ns</td>
    <td style="white-space: nowrap; text-align: right">37.50 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">22.77 M</td>
    <td style="white-space: nowrap; text-align: right">43.91 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1757.12%</td>
    <td style="white-space: nowrap; text-align: right">37.50 ns</td>
    <td style="white-space: nowrap; text-align: right">58.30 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">15.70 M</td>
    <td style="white-space: nowrap; text-align: right">63.71 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5268.33%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">11.83 M</td>
    <td style="white-space: nowrap; text-align: right">84.50 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2720.98%</td>
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
    <td style="white-space: nowrap;text-align: right">35.97 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">22.77 M</td>
    <td style="white-space: nowrap; text-align: right">1.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap; text-align: right">15.70 M</td>
    <td style="white-space: nowrap; text-align: right">2.29x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap; text-align: right">11.83 M</td>
    <td style="white-space: nowrap; text-align: right">3.04x</td>
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
    <td style="white-space: nowrap">152 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode little-endian bytes and words</td>
    <td style="white-space: nowrap">352 B</td>
    <td>2.32x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode big-endian</td>
    <td style="white-space: nowrap">152 B</td>
    <td>1.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode little-endian bytes and words</td>
    <td style="white-space: nowrap">352 B</td>
    <td>2.32x</td>
  </tr>
</table>