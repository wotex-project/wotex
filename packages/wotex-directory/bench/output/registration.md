# Registration, replacement, retrieval and lifecycle Events

`Wotex.Directory.register/4`, `replace/5` and `get/3` over synthetic Thing
Descriptions with one, 24 and 240 Properties, each with one Form, and
`Wotex.Directory.Event.from_mutation/2` deriving the `thing_updated` Event
data with the enriched Thing Description. The consumer ports are in-process:
authorization always allows, the clock is fixed, and the repository answers
from an immutable snapshot holding one entry, so the numbers cover the
Directory mechanics (authorization order, Thing Description validation,
registration information, entry and stored-entry validation) and no
persistence.


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



__Input: 1 Property__

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
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap; text-align: right">30.77 K</td>
    <td style="white-space: nowrap; text-align: right">32.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.03%</td>
    <td style="white-space: nowrap; text-align: right">31.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">46.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap; text-align: right">14.73 K</td>
    <td style="white-space: nowrap; text-align: right">67.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.39%</td>
    <td style="white-space: nowrap; text-align: right">67.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">85.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap; text-align: right">7.87 K</td>
    <td style="white-space: nowrap; text-align: right">127.07 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.03%</td>
    <td style="white-space: nowrap; text-align: right">124.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">160.20 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap; text-align: right">6.47 K</td>
    <td style="white-space: nowrap; text-align: right">154.60 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.85%</td>
    <td style="white-space: nowrap; text-align: right">151.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">194.58 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap;text-align: right">30.77 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap; text-align: right">14.73 K</td>
    <td style="white-space: nowrap; text-align: right">2.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap; text-align: right">7.87 K</td>
    <td style="white-space: nowrap; text-align: right">3.91x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap; text-align: right">6.47 K</td>
    <td style="white-space: nowrap; text-align: right">4.76x</td>
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
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap">69.51 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap">149.91 KB</td>
    <td>2.16x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap">278.24 KB</td>
    <td>4.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap">347.82 KB</td>
    <td>5.0x</td>
  </tr>
</table>



__Input: 24 Properties__

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
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap; text-align: right">5.54 K</td>
    <td style="white-space: nowrap; text-align: right">180.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.78%</td>
    <td style="white-space: nowrap; text-align: right">173.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">228.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap; text-align: right">2.45 K</td>
    <td style="white-space: nowrap; text-align: right">407.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.49%</td>
    <td style="white-space: nowrap; text-align: right">405.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">463.19 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap; text-align: right">1.33 K</td>
    <td style="white-space: nowrap; text-align: right">751.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.42%</td>
    <td style="white-space: nowrap; text-align: right">749.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">826.31 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap; text-align: right">1.08 K</td>
    <td style="white-space: nowrap; text-align: right">926.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.46%</td>
    <td style="white-space: nowrap; text-align: right">925.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1002.63 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap;text-align: right">5.54 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap; text-align: right">2.45 K</td>
    <td style="white-space: nowrap; text-align: right">2.26x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap; text-align: right">1.33 K</td>
    <td style="white-space: nowrap; text-align: right">4.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap; text-align: right">1.08 K</td>
    <td style="white-space: nowrap; text-align: right">5.13x</td>
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
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap">0.43 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap">0.97 MB</td>
    <td>2.28x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap">1.81 MB</td>
    <td>4.25x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap">2.23 MB</td>
    <td>5.24x</td>
  </tr>
</table>



__Input: 240 Properties__

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
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap; text-align: right">742.53</td>
    <td style="white-space: nowrap; text-align: right">1.35 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.69%</td>
    <td style="white-space: nowrap; text-align: right">1.35 ms</td>
    <td style="white-space: nowrap; text-align: right">1.58 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap; text-align: right">304.12</td>
    <td style="white-space: nowrap; text-align: right">3.29 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.76%</td>
    <td style="white-space: nowrap; text-align: right">3.30 ms</td>
    <td style="white-space: nowrap; text-align: right">3.55 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap; text-align: right">167.69</td>
    <td style="white-space: nowrap; text-align: right">5.96 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.12%</td>
    <td style="white-space: nowrap; text-align: right">5.96 ms</td>
    <td style="white-space: nowrap; text-align: right">6.31 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap; text-align: right">138.10</td>
    <td style="white-space: nowrap; text-align: right">7.24 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.93%</td>
    <td style="white-space: nowrap; text-align: right">7.23 ms</td>
    <td style="white-space: nowrap; text-align: right">7.70 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap;text-align: right">742.53</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap; text-align: right">304.12</td>
    <td style="white-space: nowrap; text-align: right">2.44x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap; text-align: right">167.69</td>
    <td style="white-space: nowrap; text-align: right">4.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap; text-align: right">138.10</td>
    <td style="white-space: nowrap; text-align: right">5.38x</td>
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
    <td style="white-space: nowrap">get</td>
    <td style="white-space: nowrap">3.79 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Event.from_mutation (full payload)</td>
    <td style="white-space: nowrap">8.72 MB</td>
    <td>2.3x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">register (named, created)</td>
    <td style="white-space: nowrap">16.26 MB</td>
    <td>4.29x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">replace</td>
    <td style="white-space: nowrap">20.09 MB</td>
    <td>5.3x</td>
  </tr>
</table>