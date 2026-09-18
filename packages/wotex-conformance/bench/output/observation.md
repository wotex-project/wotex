# Normalized observations and pointer projections

`Wotex.Conformance.Observation` over a `thing_description.parse` vector
whose input document declares 64 Properties and whose projection names
one, eight or 64 of them as RFC 6901 JSON Pointers. The accepted
observation maps each pointer to its Property; the rejected observation
carries one sorted error per pointer. The digest job is the canonical
SHA-256 digest the runner compares with the expectation, and the pointer
job encodes the projection with `Wotex.Conformance.Pointer.encode/1`.


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



__Input: 1 pointer__

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
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap; text-align: right">12.01 M</td>
    <td style="white-space: nowrap; text-align: right">83.27 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2083.92%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap; text-align: right">2.33 M</td>
    <td style="white-space: nowrap; text-align: right">430.06 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;936.93%</td>
    <td style="white-space: nowrap; text-align: right">416 ns</td>
    <td style="white-space: nowrap; text-align: right">542 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap; text-align: right">1.67 M</td>
    <td style="white-space: nowrap; text-align: right">599.40 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1500.50%</td>
    <td style="white-space: nowrap; text-align: right">458 ns</td>
    <td style="white-space: nowrap; text-align: right">1000 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap; text-align: right">0.56 M</td>
    <td style="white-space: nowrap; text-align: right">1778.34 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;960.60%</td>
    <td style="white-space: nowrap; text-align: right">1333 ns</td>
    <td style="white-space: nowrap; text-align: right">2417 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap; text-align: right">0.37 M</td>
    <td style="white-space: nowrap; text-align: right">2707.21 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;194.20%</td>
    <td style="white-space: nowrap; text-align: right">2458 ns</td>
    <td style="white-space: nowrap; text-align: right">6125 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap;text-align: right">12.01 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap; text-align: right">2.33 M</td>
    <td style="white-space: nowrap; text-align: right">5.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap; text-align: right">1.67 M</td>
    <td style="white-space: nowrap; text-align: right">7.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap; text-align: right">0.56 M</td>
    <td style="white-space: nowrap; text-align: right">21.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap; text-align: right">0.37 M</td>
    <td style="white-space: nowrap; text-align: right">32.51x</td>
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
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap">56 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap">520 B</td>
    <td>9.29x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap">408 B</td>
    <td>7.29x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap">976 B</td>
    <td>17.43x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap">8856 B</td>
    <td>158.14x</td>
  </tr>
</table>



__Input: 8 pointers__

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
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap; text-align: right">11798.39 K</td>
    <td style="white-space: nowrap; text-align: right">0.0848 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;603.64%</td>
    <td style="white-space: nowrap; text-align: right">0.0830 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.125 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap; text-align: right">310.90 K</td>
    <td style="white-space: nowrap; text-align: right">3.22 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;165.17%</td>
    <td style="white-space: nowrap; text-align: right">3.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap; text-align: right">224.41 K</td>
    <td style="white-space: nowrap; text-align: right">4.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;467.72%</td>
    <td style="white-space: nowrap; text-align: right">3.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap; text-align: right">82.78 K</td>
    <td style="white-space: nowrap; text-align: right">12.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;40.88%</td>
    <td style="white-space: nowrap; text-align: right">11.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">25.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap; text-align: right">66.53 K</td>
    <td style="white-space: nowrap; text-align: right">15.03 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.32%</td>
    <td style="white-space: nowrap; text-align: right">14.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">22.33 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap;text-align: right">11798.39 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap; text-align: right">310.90 K</td>
    <td style="white-space: nowrap; text-align: right">37.95x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap; text-align: right">224.41 K</td>
    <td style="white-space: nowrap; text-align: right">52.57x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap; text-align: right">82.78 K</td>
    <td style="white-space: nowrap; text-align: right">142.53x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap; text-align: right">66.53 K</td>
    <td style="white-space: nowrap; text-align: right">177.35x</td>
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
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap">0.0547 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap">4.14 KB</td>
    <td>75.71x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap">3.29 KB</td>
    <td>60.14x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap">7.52 KB</td>
    <td>137.43x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap">54.52 KB</td>
    <td>997.0x</td>
  </tr>
</table>



__Input: 64 pointers__

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
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap; text-align: right">12186.16 K</td>
    <td style="white-space: nowrap; text-align: right">0.0821 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;456.80%</td>
    <td style="white-space: nowrap; text-align: right">0.0830 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.125 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap; text-align: right">38.31 K</td>
    <td style="white-space: nowrap; text-align: right">26.11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.39%</td>
    <td style="white-space: nowrap; text-align: right">25.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">34 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap; text-align: right">26.72 K</td>
    <td style="white-space: nowrap; text-align: right">37.43 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.93%</td>
    <td style="white-space: nowrap; text-align: right">33.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">71.87 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap; text-align: right">8.86 K</td>
    <td style="white-space: nowrap; text-align: right">112.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.25%</td>
    <td style="white-space: nowrap; text-align: right">110.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">137.15 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap; text-align: right">6.86 K</td>
    <td style="white-space: nowrap; text-align: right">145.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.02%</td>
    <td style="white-space: nowrap; text-align: right">138.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">238.51 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap;text-align: right">12186.16 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap; text-align: right">38.31 K</td>
    <td style="white-space: nowrap; text-align: right">318.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap; text-align: right">26.72 K</td>
    <td style="white-space: nowrap; text-align: right">456.14x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap; text-align: right">8.86 K</td>
    <td style="white-space: nowrap; text-align: right">1374.89x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap; text-align: right">6.86 K</td>
    <td style="white-space: nowrap; text-align: right">1777.67x</td>
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
    <td style="white-space: nowrap">validate accepted observation</td>
    <td style="white-space: nowrap">0.0547 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode projection pointers</td>
    <td style="white-space: nowrap">33.18 KB</td>
    <td>606.71x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate vector input</td>
    <td style="white-space: nowrap">31.89 KB</td>
    <td>583.14x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate rejected observation</td>
    <td style="white-space: nowrap">68.45 KB</td>
    <td>1251.71x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">digest accepted observation</td>
    <td style="white-space: nowrap">426.05 KB</td>
    <td>7790.71x</td>
  </tr>
</table>