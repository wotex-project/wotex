# Coil bit packing and response validation

`Wotex.Modbus.Command.new/4` admission and `Wotex.Modbus.Codec.encode/2`
of a write multiple coils command (function 15, bit packing), and
`Wotex.Modbus.Codec.response/3` of the read coils (function 1) response,
which checks the byte count before unpacking one boolean per coil, and of
the function 15 echo, over eight, 256 and 1968 coils. 1968 is the function
15 quantity limit.


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



__Input: 1968 coils__

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
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">64.93 K</td>
    <td style="white-space: nowrap; text-align: right">15.40 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.53%</td>
    <td style="white-space: nowrap; text-align: right">14.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">22.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">52.48 K</td>
    <td style="white-space: nowrap; text-align: right">19.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.32%</td>
    <td style="white-space: nowrap; text-align: right">18.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">27.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap; text-align: right">48.29 K</td>
    <td style="white-space: nowrap; text-align: right">20.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.18%</td>
    <td style="white-space: nowrap; text-align: right">20.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">28.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">21.51 K</td>
    <td style="white-space: nowrap; text-align: right">46.49 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.99%</td>
    <td style="white-space: nowrap; text-align: right">45.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">73.75 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap;text-align: right">64.93 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">52.48 K</td>
    <td style="white-space: nowrap; text-align: right">1.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap; text-align: right">48.29 K</td>
    <td style="white-space: nowrap; text-align: right">1.34x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">21.51 K</td>
    <td style="white-space: nowrap; text-align: right">3.02x</td>
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
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap">31.52 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap">30.93 KB</td>
    <td>0.98x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap">31.42 KB</td>
    <td>1.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap">368.09 KB</td>
    <td>11.68x</td>
  </tr>
</table>



__Input: 256 coils__

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
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">472.82 K</td>
    <td style="white-space: nowrap; text-align: right">2.11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;280.19%</td>
    <td style="white-space: nowrap; text-align: right">2.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">371.97 K</td>
    <td style="white-space: nowrap; text-align: right">2.69 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;181.63%</td>
    <td style="white-space: nowrap; text-align: right">2.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap; text-align: right">340.36 K</td>
    <td style="white-space: nowrap; text-align: right">2.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;158.98%</td>
    <td style="white-space: nowrap; text-align: right">2.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">173.08 K</td>
    <td style="white-space: nowrap; text-align: right">5.78 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;70.96%</td>
    <td style="white-space: nowrap; text-align: right">5.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">13.21 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap;text-align: right">472.82 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap; text-align: right">371.97 K</td>
    <td style="white-space: nowrap; text-align: right">1.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap; text-align: right">340.36 K</td>
    <td style="white-space: nowrap; text-align: right">1.39x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">173.08 K</td>
    <td style="white-space: nowrap; text-align: right">2.73x</td>
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
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap">4.77 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap">4.18 KB</td>
    <td>0.88x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap">4.67 KB</td>
    <td>0.98x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap">48.73 KB</td>
    <td>10.21x</td>
  </tr>
</table>



__Input: 8 coils__

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
    <td style="white-space: nowrap; text-align: right">10.62 M</td>
    <td style="white-space: nowrap; text-align: right">94.16 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3870.65%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap; text-align: right">6.60 M</td>
    <td style="white-space: nowrap; text-align: right">151.54 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2764.41%</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
    <td style="white-space: nowrap; text-align: right">250 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">6.33 M</td>
    <td style="white-space: nowrap; text-align: right">158.05 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2575.14%</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
    <td style="white-space: nowrap; text-align: right">250 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">3.56 M</td>
    <td style="white-space: nowrap; text-align: right">280.62 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1493.64%</td>
    <td style="white-space: nowrap; text-align: right">250 ns</td>
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
    <td style="white-space: nowrap">admit write command</td>
    <td style="white-space: nowrap;text-align: right">10.62 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap; text-align: right">6.60 M</td>
    <td style="white-space: nowrap; text-align: right">1.61x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap; text-align: right">6.33 M</td>
    <td style="white-space: nowrap; text-align: right">1.68x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap; text-align: right">3.56 M</td>
    <td style="white-space: nowrap; text-align: right">2.98x</td>
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
    <td style="white-space: nowrap">312 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate write echo</td>
    <td style="white-space: nowrap">816 B</td>
    <td>2.62x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate read response</td>
    <td style="white-space: nowrap">896 B</td>
    <td>2.87x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode write request</td>
    <td style="white-space: nowrap">2432 B</td>
    <td>7.79x</td>
  </tr>
</table>