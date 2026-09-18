# Register request encoding and response validation

`Wotex.Modbus.Command.new/4` admission of a write multiple holding
registers command (function 16), `Wotex.Modbus.Codec.encode/2` of the
read holding registers (function 3) and function 16 requests, and
`Wotex.Modbus.Codec.decode/1` and `Wotex.Modbus.Codec.response/3` of the
function 3 response ADU, over one, 16 and 123 registers. 123 is the
function 16 quantity limit. Response validation includes command
revalidation, transaction and Unit Identifier correlation and the byte
count check.


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



__Input: 1 register__

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
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">17.64 M</td>
    <td style="white-space: nowrap; text-align: right">56.70 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7465.90%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap; text-align: right">17.60 M</td>
    <td style="white-space: nowrap; text-align: right">56.81 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8385.94%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">14.10 M</td>
    <td style="white-space: nowrap; text-align: right">70.94 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1101.37%</td>
    <td style="white-space: nowrap; text-align: right">62.50 ns</td>
    <td style="white-space: nowrap; text-align: right">100 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap; text-align: right">9.84 M</td>
    <td style="white-space: nowrap; text-align: right">101.64 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3492.31%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">6.94 M</td>
    <td style="white-space: nowrap; text-align: right">144.12 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2895.28%</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
    <td style="white-space: nowrap; text-align: right">208 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap;text-align: right">17.64 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap; text-align: right">17.60 M</td>
    <td style="white-space: nowrap; text-align: right">1.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">14.10 M</td>
    <td style="white-space: nowrap; text-align: right">1.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap; text-align: right">9.84 M</td>
    <td style="white-space: nowrap; text-align: right">1.79x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">6.94 M</td>
    <td style="white-space: nowrap; text-align: right">2.54x</td>
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
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap">184 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap">144 B</td>
    <td>0.78x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap">680 B</td>
    <td>3.7x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap">680 B</td>
    <td>3.7x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap">792 B</td>
    <td>4.3x</td>
  </tr>
</table>



__Input: 123 registers__

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
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap; text-align: right">37.38 M</td>
    <td style="white-space: nowrap; text-align: right">26.75 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;38.81%</td>
    <td style="white-space: nowrap; text-align: right">25 ns</td>
    <td style="white-space: nowrap; text-align: right">41.70 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap; text-align: right">9.29 M</td>
    <td style="white-space: nowrap; text-align: right">107.61 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4924.35%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">2.23 M</td>
    <td style="white-space: nowrap; text-align: right">448.23 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1230.08%</td>
    <td style="white-space: nowrap; text-align: right">417 ns</td>
    <td style="white-space: nowrap; text-align: right">542 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">1.45 M</td>
    <td style="white-space: nowrap; text-align: right">689.16 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;799.17%</td>
    <td style="white-space: nowrap; text-align: right">666 ns</td>
    <td style="white-space: nowrap; text-align: right">875 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">0.46 M</td>
    <td style="white-space: nowrap; text-align: right">2153.47 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;295.05%</td>
    <td style="white-space: nowrap; text-align: right">1916 ns</td>
    <td style="white-space: nowrap; text-align: right">4250 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap;text-align: right">37.38 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap; text-align: right">9.29 M</td>
    <td style="white-space: nowrap; text-align: right">4.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">2.23 M</td>
    <td style="white-space: nowrap; text-align: right">16.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">1.45 M</td>
    <td style="white-space: nowrap; text-align: right">25.76x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">0.46 M</td>
    <td style="white-space: nowrap; text-align: right">80.5x</td>
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
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap">160 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap">360 B</td>
    <td>2.25x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap">184 B</td>
    <td>1.15x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap">2312 B</td>
    <td>14.45x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap">5464 B</td>
    <td>34.15x</td>
  </tr>
</table>



__Input: 16 registers__

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
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap; text-align: right">21.23 M</td>
    <td style="white-space: nowrap; text-align: right">47.11 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;734.17%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap; text-align: right">13.84 M</td>
    <td style="white-space: nowrap; text-align: right">72.27 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1048.29%</td>
    <td style="white-space: nowrap; text-align: right">66.60 ns</td>
    <td style="white-space: nowrap; text-align: right">95.90 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">10.58 M</td>
    <td style="white-space: nowrap; text-align: right">94.56 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4365.46%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">8.62 M</td>
    <td style="white-space: nowrap; text-align: right">116.05 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3349.41%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">208 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">3.25 M</td>
    <td style="white-space: nowrap; text-align: right">307.41 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1112.84%</td>
    <td style="white-space: nowrap; text-align: right">291 ns</td>
    <td style="white-space: nowrap; text-align: right">417 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap;text-align: right">21.23 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap; text-align: right">13.84 M</td>
    <td style="white-space: nowrap; text-align: right">1.53x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">10.58 M</td>
    <td style="white-space: nowrap; text-align: right">2.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">8.62 M</td>
    <td style="white-space: nowrap; text-align: right">2.46x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">3.25 M</td>
    <td style="white-space: nowrap; text-align: right">6.53x</td>
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
    <td style="white-space: nowrap">decode response ADU</td>
    <td style="white-space: nowrap">176 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode read request</td>
    <td style="white-space: nowrap">680 B</td>
    <td>3.86x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap">184 B</td>
    <td>1.05x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap">920 B</td>
    <td>5.23x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap">1480 B</td>
    <td>8.41x</td>
  </tr>
</table>