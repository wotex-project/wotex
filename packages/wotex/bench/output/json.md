# Bounded JSON admission and canonical encoding

`Wotex.JSON.decode/2` with the default `Wotex.JSON.Limits` and
`Wotex.JSON.encode/2` over the Thing Description documents of the
Thing Description benchmark.


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



__Input: 1 affordance__

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
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap; text-align: right">122.11 K</td>
    <td style="white-space: nowrap; text-align: right">8.19 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;29.07%</td>
    <td style="white-space: nowrap; text-align: right">7.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">18 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap; text-align: right">118.94 K</td>
    <td style="white-space: nowrap; text-align: right">8.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.64%</td>
    <td style="white-space: nowrap; text-align: right">8.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">17.46 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap;text-align: right">122.11 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap; text-align: right">118.94 K</td>
    <td style="white-space: nowrap; text-align: right">1.03x</td>
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
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap">14.25 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap">20.60 KB</td>
    <td>1.45x</td>
  </tr>
</table>



__Input: 24 affordances__

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
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap; text-align: right">6.40 K</td>
    <td style="white-space: nowrap; text-align: right">156.22 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.73%</td>
    <td style="white-space: nowrap; text-align: right">153.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">198.53 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap; text-align: right">6.20 K</td>
    <td style="white-space: nowrap; text-align: right">161.28 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.58%</td>
    <td style="white-space: nowrap; text-align: right">158.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">229.00 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap;text-align: right">6.40 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap; text-align: right">6.20 K</td>
    <td style="white-space: nowrap; text-align: right">1.03x</td>
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
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap">356.26 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap">258.77 KB</td>
    <td>0.73x</td>
  </tr>
</table>



__Input: 240 affordances__

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
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap; text-align: right">625.87</td>
    <td style="white-space: nowrap; text-align: right">1.60 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.72%</td>
    <td style="white-space: nowrap; text-align: right">1.59 ms</td>
    <td style="white-space: nowrap; text-align: right">1.83 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap; text-align: right">623.82</td>
    <td style="white-space: nowrap; text-align: right">1.60 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.32%</td>
    <td style="white-space: nowrap; text-align: right">1.58 ms</td>
    <td style="white-space: nowrap; text-align: right">1.82 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap;text-align: right">625.87</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap; text-align: right">623.82</td>
    <td style="white-space: nowrap; text-align: right">1.0x</td>
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
    <td style="white-space: nowrap">encode with sorted keys</td>
    <td style="white-space: nowrap">3.40 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap">2.48 MB</td>
    <td>0.73x</td>
  </tr>
</table>