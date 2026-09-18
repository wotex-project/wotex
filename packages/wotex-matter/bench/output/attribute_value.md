# Matter attribute values and bounded TLV

`Wotex.Matter.Descriptor.to_element/4` and `from_element/4` convert between
admitted schema values and one anonymous TLV element through the descriptor
registry; `Wotex.Matter.TLV.encode/1` (which verifies its output by decoding
it again) and `decode/1` convert that element to and from bytes. Inputs are
a Thermostat OccupiedHeatingSetpoint write (one node), a Descriptor
ServerList read of 64 clusters (65 nodes) and an AccessControl ACL write of
32 entries, each with four CASE subjects and two targets (545 nodes).


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



__Input: ACL of 32 entries__

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
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">18.20 K</td>
    <td style="white-space: nowrap; text-align: right">54.95 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.92%</td>
    <td style="white-space: nowrap; text-align: right">53.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">111.23 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">11.17 K</td>
    <td style="white-space: nowrap; text-align: right">89.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.43%</td>
    <td style="white-space: nowrap; text-align: right">86.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">207.35 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap; text-align: right">6.01 K</td>
    <td style="white-space: nowrap; text-align: right">166.47 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.94%</td>
    <td style="white-space: nowrap; text-align: right">158.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">293.91 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap; text-align: right">5.81 K</td>
    <td style="white-space: nowrap; text-align: right">172.24 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.77%</td>
    <td style="white-space: nowrap; text-align: right">164.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">304.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap;text-align: right">18.20 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">11.17 K</td>
    <td style="white-space: nowrap; text-align: right">1.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap; text-align: right">6.01 K</td>
    <td style="white-space: nowrap; text-align: right">3.03x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap; text-align: right">5.81 K</td>
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
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap">420.08 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap">520.20 KB</td>
    <td>1.24x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap">994.80 KB</td>
    <td>2.37x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap">978.88 KB</td>
    <td>2.33x</td>
  </tr>
</table>



__Input: ServerList of 64 clusters__

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
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">279.70 K</td>
    <td style="white-space: nowrap; text-align: right">3.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;92.82%</td>
    <td style="white-space: nowrap; text-align: right">3.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">11.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">118.58 K</td>
    <td style="white-space: nowrap; text-align: right">8.43 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;123.94%</td>
    <td style="white-space: nowrap; text-align: right">6.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">22.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap; text-align: right">85.99 K</td>
    <td style="white-space: nowrap; text-align: right">11.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.10%</td>
    <td style="white-space: nowrap; text-align: right">10.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">18.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap; text-align: right">83.40 K</td>
    <td style="white-space: nowrap; text-align: right">11.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;24.41%</td>
    <td style="white-space: nowrap; text-align: right">10.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">19.33 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap;text-align: right">279.70 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">118.58 K</td>
    <td style="white-space: nowrap; text-align: right">2.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap; text-align: right">85.99 K</td>
    <td style="white-space: nowrap; text-align: right">3.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap; text-align: right">83.40 K</td>
    <td style="white-space: nowrap; text-align: right">3.35x</td>
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
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap">37.01 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap">47.16 KB</td>
    <td>1.27x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap">91.64 KB</td>
    <td>2.48x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap">86.92 KB</td>
    <td>2.35x</td>
  </tr>
</table>



__Input: i16 setpoint__

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
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">29.61 M</td>
    <td style="white-space: nowrap; text-align: right">33.78 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2849.89%</td>
    <td style="white-space: nowrap; text-align: right">29.10 ns</td>
    <td style="white-space: nowrap; text-align: right">45.90 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">19.78 M</td>
    <td style="white-space: nowrap; text-align: right">50.56 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1703.57%</td>
    <td style="white-space: nowrap; text-align: right">45.80 ns</td>
    <td style="white-space: nowrap; text-align: right">70.80 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap; text-align: right">5.17 M</td>
    <td style="white-space: nowrap; text-align: right">193.43 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2569.30%</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
    <td style="white-space: nowrap; text-align: right">292 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap; text-align: right">3.77 M</td>
    <td style="white-space: nowrap; text-align: right">265.17 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2038.55%</td>
    <td style="white-space: nowrap; text-align: right">209 ns</td>
    <td style="white-space: nowrap; text-align: right">375 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap;text-align: right">29.61 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap; text-align: right">19.78 M</td>
    <td style="white-space: nowrap; text-align: right">1.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap; text-align: right">5.17 M</td>
    <td style="white-space: nowrap; text-align: right">5.73x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap; text-align: right">3.77 M</td>
    <td style="white-space: nowrap; text-align: right">7.85x</td>
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
    <td style="white-space: nowrap">decode TLV bytes</td>
    <td style="white-space: nowrap">0.38 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode TLV bytes</td>
    <td style="white-space: nowrap">0.57 KB</td>
    <td>1.49x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">schema value to TLV element</td>
    <td style="white-space: nowrap">1.46 KB</td>
    <td>3.82x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">TLV element to schema value</td>
    <td style="white-space: nowrap">1.83 KB</td>
    <td>4.78x</td>
  </tr>
</table>