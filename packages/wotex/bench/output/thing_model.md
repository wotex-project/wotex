# Thing Model parsing

`Wotex.ThingModel.parse/2` over synthetic Thing Models whose Properties are
all listed in `tm:optional`.


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
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">30.89 K</td>
    <td style="white-space: nowrap; text-align: right">32.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.69%</td>
    <td style="white-space: nowrap; text-align: right">30.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">44.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap;text-align: right">30.89 K</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap">52.66 KB</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">2.54 K</td>
    <td style="white-space: nowrap; text-align: right">394.11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.63%</td>
    <td style="white-space: nowrap; text-align: right">392.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">474.02 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap;text-align: right">2.54 K</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap">561.56 KB</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap; text-align: right">272.51</td>
    <td style="white-space: nowrap; text-align: right">3.67 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.70%</td>
    <td style="white-space: nowrap; text-align: right">3.66 ms</td>
    <td style="white-space: nowrap; text-align: right">3.95 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap;text-align: right">272.51</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">parse and validate</td>
    <td style="white-space: nowrap">5.26 MB</td>
    <td>&nbsp;</td>
  </tr>
</table>