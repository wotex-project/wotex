# Thing Description parsing, validation and encoding

`Wotex.ThingDescription` over synthetic Thing Descriptions with one, 24 and
240 Properties plus a third as many Actions and Events, each with one Form.
Parsing includes bounded JSON admission with the default limits.


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
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap; text-align: right">117.99 K</td>
    <td style="white-space: nowrap; text-align: right">8.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;26.42%</td>
    <td style="white-space: nowrap; text-align: right">8.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">17.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap; text-align: right">115.87 K</td>
    <td style="white-space: nowrap; text-align: right">8.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.13%</td>
    <td style="white-space: nowrap; text-align: right">8.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">17.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap; text-align: right">34.26 K</td>
    <td style="white-space: nowrap; text-align: right">29.19 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.44%</td>
    <td style="white-space: nowrap; text-align: right">28.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">42.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">26.43 K</td>
    <td style="white-space: nowrap; text-align: right">37.84 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.88%</td>
    <td style="white-space: nowrap; text-align: right">36.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">51.67 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap;text-align: right">117.99 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap; text-align: right">115.87 K</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap; text-align: right">34.26 K</td>
    <td style="white-space: nowrap; text-align: right">3.44x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">26.43 K</td>
    <td style="white-space: nowrap; text-align: right">4.46x</td>
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
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap">14.38 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap">20.60 KB</td>
    <td>1.43x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap">67.42 KB</td>
    <td>4.69x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap">82.66 KB</td>
    <td>5.75x</td>
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
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap; text-align: right">6.25 K</td>
    <td style="white-space: nowrap; text-align: right">160.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.62%</td>
    <td style="white-space: nowrap; text-align: right">158.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">196.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap; text-align: right">6.11 K</td>
    <td style="white-space: nowrap; text-align: right">163.78 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.61%</td>
    <td style="white-space: nowrap; text-align: right">160.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">239.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap; text-align: right">3.23 K</td>
    <td style="white-space: nowrap; text-align: right">309.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.19%</td>
    <td style="white-space: nowrap; text-align: right">305 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">385.45 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">2.15 K</td>
    <td style="white-space: nowrap; text-align: right">464.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.37%</td>
    <td style="white-space: nowrap; text-align: right">459.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">541.47 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap;text-align: right">6.25 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap; text-align: right">6.11 K</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap; text-align: right">3.23 K</td>
    <td style="white-space: nowrap; text-align: right">1.93x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">2.15 K</td>
    <td style="white-space: nowrap; text-align: right">2.9x</td>
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
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap">356.45 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap">258.88 KB</td>
    <td>0.73x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap">711.98 KB</td>
    <td>2.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap">973.70 KB</td>
    <td>2.73x</td>
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
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap; text-align: right">621.06</td>
    <td style="white-space: nowrap; text-align: right">1.61 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.64%</td>
    <td style="white-space: nowrap; text-align: right">1.60 ms</td>
    <td style="white-space: nowrap; text-align: right">1.75 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap; text-align: right">603.83</td>
    <td style="white-space: nowrap; text-align: right">1.66 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.75%</td>
    <td style="white-space: nowrap; text-align: right">1.61 ms</td>
    <td style="white-space: nowrap; text-align: right">1.99 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap; text-align: right">351.79</td>
    <td style="white-space: nowrap; text-align: right">2.84 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;22.18%</td>
    <td style="white-space: nowrap; text-align: right">2.51 ms</td>
    <td style="white-space: nowrap; text-align: right">4.25 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">244.94</td>
    <td style="white-space: nowrap; text-align: right">4.08 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.56%</td>
    <td style="white-space: nowrap; text-align: right">4.08 ms</td>
    <td style="white-space: nowrap; text-align: right">4.37 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap;text-align: right">621.06</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap; text-align: right">603.83</td>
    <td style="white-space: nowrap; text-align: right">1.03x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap; text-align: right">351.79</td>
    <td style="white-space: nowrap; text-align: right">1.77x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">244.94</td>
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
    <td style="white-space: nowrap">encode canonical</td>
    <td style="white-space: nowrap">3.40 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse without validation</td>
    <td style="white-space: nowrap">2.48 MB</td>
    <td>0.73x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate</td>
    <td style="white-space: nowrap">6.56 MB</td>
    <td>1.93x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap">9.05 MB</td>
    <td>2.66x</td>
  </tr>
</table>