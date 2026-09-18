# Row encoding into a lazy Nx batch

`Wotex.Nx.Encoder.encode/3` over 32 rows of 4 features, 128 rows of 16
features and 512 rows of 64 features, each a scalar `number` Property in
degrees Celsius with a `{:fill, 0.0}` missing-value policy and matching
units, so no unit converter runs. Encoding validates every row and value,
then builds the per-row value and mask tuples and quality vectors on the
default `Nx.BinaryBackend`; the lazy `Nx.Batch` stack is not materialized.
The second job leaves every fourth cell empty so the fill path supplies it.


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



__Input: 16 features x 128 rows__

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
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap; text-align: right">450.34</td>
    <td style="white-space: nowrap; text-align: right">2.22 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.06%</td>
    <td style="white-space: nowrap; text-align: right">2.18 ms</td>
    <td style="white-space: nowrap; text-align: right">2.74 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap; text-align: right">401.07</td>
    <td style="white-space: nowrap; text-align: right">2.49 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.60%</td>
    <td style="white-space: nowrap; text-align: right">2.46 ms</td>
    <td style="white-space: nowrap; text-align: right">3.03 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap;text-align: right">450.34</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap; text-align: right">401.07</td>
    <td style="white-space: nowrap; text-align: right">1.12x</td>
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
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap">9.75 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap">11.49 MB</td>
    <td>1.18x</td>
  </tr>
</table>



__Input: 4 features x 32 rows__

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
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap; text-align: right">6.18 K</td>
    <td style="white-space: nowrap; text-align: right">161.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.40%</td>
    <td style="white-space: nowrap; text-align: right">159.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">245.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap; text-align: right">5.11 K</td>
    <td style="white-space: nowrap; text-align: right">195.51 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;26.01%</td>
    <td style="white-space: nowrap; text-align: right">178.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">365.80 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap;text-align: right">6.18 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap; text-align: right">5.11 K</td>
    <td style="white-space: nowrap; text-align: right">1.21x</td>
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
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap">702.70 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap">812.98 KB</td>
    <td>1.16x</td>
  </tr>
</table>



__Input: 64 features x 512 rows__

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
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap; text-align: right">29.34</td>
    <td style="white-space: nowrap; text-align: right">34.08 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.75%</td>
    <td style="white-space: nowrap; text-align: right">33.10 ms</td>
    <td style="white-space: nowrap; text-align: right">48.67 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap; text-align: right">25.60</td>
    <td style="white-space: nowrap; text-align: right">39.06 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.99%</td>
    <td style="white-space: nowrap; text-align: right">37.77 ms</td>
    <td style="white-space: nowrap; text-align: right">50.67 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap;text-align: right">29.34</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap; text-align: right">25.60</td>
    <td style="white-space: nowrap; text-align: right">1.15x</td>
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
    <td style="white-space: nowrap">encode (every fourth cell filled)</td>
    <td style="white-space: nowrap">151.61 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode (every cell observed)</td>
    <td style="white-space: nowrap">179.36 MB</td>
    <td>1.18x</td>
  </tr>
</table>