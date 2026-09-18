# Topic Name and Topic Filter handling

`Wotex.Binding.MQTT.Topic` and SUBSCRIBE command construction over one, 16
and 256 Topic Filters, 256 being the package's filter cardinality limit.
The filters rotate through an exact filter, a single-level `+` wildcard, a
multi-level `#` wildcard and an MQTT 5 `$share` subscription. The match job
tests one Topic Name against every filter, validating both on each call,
as `Wotex.Binding.MQTT.Transport` does for every delivery;
`Wotex.Binding.MQTT.Command.subscribe/4` validates the list and the QoS.


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



__Input: 1 filter__

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
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap; text-align: right">1632.02 K</td>
    <td style="white-space: nowrap; text-align: right">0.61 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;600.35%</td>
    <td style="white-space: nowrap; text-align: right">0.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap; text-align: right">524.59 K</td>
    <td style="white-space: nowrap; text-align: right">1.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;290.94%</td>
    <td style="white-space: nowrap; text-align: right">1.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap; text-align: right">434.18 K</td>
    <td style="white-space: nowrap; text-align: right">2.30 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;202.83%</td>
    <td style="white-space: nowrap; text-align: right">2.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap; text-align: right">363.03 K</td>
    <td style="white-space: nowrap; text-align: right">2.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;211.12%</td>
    <td style="white-space: nowrap; text-align: right">2.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap;text-align: right">1632.02 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap; text-align: right">524.59 K</td>
    <td style="white-space: nowrap; text-align: right">3.11x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap; text-align: right">434.18 K</td>
    <td style="white-space: nowrap; text-align: right">3.76x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap; text-align: right">363.03 K</td>
    <td style="white-space: nowrap; text-align: right">4.5x</td>
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
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap">0.0703 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap">0.84 KB</td>
    <td>12.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap">1.80 KB</td>
    <td>25.67x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap">1.02 KB</td>
    <td>14.56x</td>
  </tr>
</table>



__Input: 16 filters__

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
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap; text-align: right">107.93 K</td>
    <td style="white-space: nowrap; text-align: right">9.26 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;26.65%</td>
    <td style="white-space: nowrap; text-align: right">8.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">14.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap; text-align: right">37.68 K</td>
    <td style="white-space: nowrap; text-align: right">26.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.12%</td>
    <td style="white-space: nowrap; text-align: right">25.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">36.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap; text-align: right">35.92 K</td>
    <td style="white-space: nowrap; text-align: right">27.84 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.59%</td>
    <td style="white-space: nowrap; text-align: right">29.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">38.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap; text-align: right">24.72 K</td>
    <td style="white-space: nowrap; text-align: right">40.45 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.97%</td>
    <td style="white-space: nowrap; text-align: right">38.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">53.21 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap;text-align: right">107.93 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap; text-align: right">37.68 K</td>
    <td style="white-space: nowrap; text-align: right">2.86x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap; text-align: right">35.92 K</td>
    <td style="white-space: nowrap; text-align: right">3.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap; text-align: right">24.72 K</td>
    <td style="white-space: nowrap; text-align: right">4.37x</td>
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
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap">1.13 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap">12.97 KB</td>
    <td>11.53x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap">14.05 KB</td>
    <td>12.49x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap">21.12 KB</td>
    <td>18.77x</td>
  </tr>
</table>



__Input: 256 filters__

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
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap; text-align: right">7.19 K</td>
    <td style="white-space: nowrap; text-align: right">139.10 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.26%</td>
    <td style="white-space: nowrap; text-align: right">136.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">162.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap; text-align: right">2.38 K</td>
    <td style="white-space: nowrap; text-align: right">420.30 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.06%</td>
    <td style="white-space: nowrap; text-align: right">407.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">515.11 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap; text-align: right">2.28 K</td>
    <td style="white-space: nowrap; text-align: right">437.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.38%</td>
    <td style="white-space: nowrap; text-align: right">411.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">523.51 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap; text-align: right">1.53 K</td>
    <td style="white-space: nowrap; text-align: right">654.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.29%</td>
    <td style="white-space: nowrap; text-align: right">635.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">794.39 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap;text-align: right">7.19 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap; text-align: right">2.38 K</td>
    <td style="white-space: nowrap; text-align: right">3.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap; text-align: right">2.28 K</td>
    <td style="white-space: nowrap; text-align: right">3.15x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap; text-align: right">1.53 K</td>
    <td style="white-space: nowrap; text-align: right">4.7x</td>
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
    <td style="white-space: nowrap">validate_name/1 for each Topic Name</td>
    <td style="white-space: nowrap">18 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">normalize_filters/1</td>
    <td style="white-space: nowrap">211.72 KB</td>
    <td>11.76x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Command.subscribe/4</td>
    <td style="white-space: nowrap">212.20 KB</td>
    <td>11.79x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">matches?/2 of one Topic Name against each filter</td>
    <td style="white-space: nowrap">341.63 KB</td>
    <td>18.98x</td>
  </tr>
</table>