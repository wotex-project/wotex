# Thread Form mapping and Runtime transport requests

Read-only Property reads of the device role, RLOC16 and network name,
selected from `thread+unix` Forms by `Wotex.Runtime.FormSelector` with a
binding profile declared by the benchmark (the package defines none).
`Wotex.Thread.Mapping.command/4` maps the Form href to a management
request and its controller target. The `request/3` callback of
`Wotex.Thread.Transport` adds the target check, deadline budget, session
open and close, request validation in `Wotex.Thread.send/2` and the
Runtime Result. The client is an in-process `Wotex.Thread.Client`
answering from prepared values; no daemon socket is opened.


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



__Input: network-name__

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
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap; text-align: right">588.01 K</td>
    <td style="white-space: nowrap; text-align: right">1.70 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;444.09%</td>
    <td style="white-space: nowrap; text-align: right">1.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">468.54 K</td>
    <td style="white-space: nowrap; text-align: right">2.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;337.29%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.04 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap;text-align: right">588.01 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">468.54 K</td>
    <td style="white-space: nowrap; text-align: right">1.25x</td>
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
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap">2.27 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap">3.11 KB</td>
    <td>1.37x</td>
  </tr>
</table>



__Input: rloc16__

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
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap; text-align: right">586.64 K</td>
    <td style="white-space: nowrap; text-align: right">1.70 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;436.77%</td>
    <td style="white-space: nowrap; text-align: right">1.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">467.89 K</td>
    <td style="white-space: nowrap; text-align: right">2.14 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;345.56%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
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
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap;text-align: right">586.64 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">467.89 K</td>
    <td style="white-space: nowrap; text-align: right">1.25x</td>
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
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap">2.27 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap">3.08 KB</td>
    <td>1.36x</td>
  </tr>
</table>



__Input: state__

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
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap; text-align: right">571.50 K</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;442.39%</td>
    <td style="white-space: nowrap; text-align: right">1.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">470.85 K</td>
    <td style="white-space: nowrap; text-align: right">2.12 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;368.52%</td>
    <td style="white-space: nowrap; text-align: right">1.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.96 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap;text-align: right">571.50 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">470.85 K</td>
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
    <td style="white-space: nowrap">map Form to management request</td>
    <td style="white-space: nowrap">2.33 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">transport request through an in-process client</td>
    <td style="white-space: nowrap">3.11 KB</td>
    <td>1.34x</td>
  </tr>
</table>