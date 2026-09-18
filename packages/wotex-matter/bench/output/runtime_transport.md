# Matter Form mapping and Runtime transport requests

A Property read (OnOff), a Property write (Thermostat
OccupiedHeatingSetpoint) and an Action invocation (On/Off Toggle) selected
from `matter` Forms by `Wotex.Runtime.FormSelector`.
`Wotex.Matter.Mapping.command/4` maps the Form href to a concrete request.
The `request/3` callback of `Wotex.Matter.Transport` adds the fabric target
check, input preflight, deadline budget, session open and close, the client
call and the Runtime Result, through the one-shot profile and through the
controller profile, whose typed services validate Descriptor values and
reports. The client is an in-process `Wotex.Matter.Client` answering from
prepared values; the failure job has it reject every request with
`:transport_unavailable`, which the facade classifies (unknown effect for
writes and invokes).


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



__Input: invokeaction__

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
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap; text-align: right">515.78 K</td>
    <td style="white-space: nowrap; text-align: right">1.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;359.23%</td>
    <td style="white-space: nowrap; text-align: right">1.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.71 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">257.46 K</td>
    <td style="white-space: nowrap; text-align: right">3.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;177.08%</td>
    <td style="white-space: nowrap; text-align: right">3.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">237.66 K</td>
    <td style="white-space: nowrap; text-align: right">4.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;124.40%</td>
    <td style="white-space: nowrap; text-align: right">3.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">12.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">236.36 K</td>
    <td style="white-space: nowrap; text-align: right">4.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;118.99%</td>
    <td style="white-space: nowrap; text-align: right">3.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">13.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap;text-align: right">515.78 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">257.46 K</td>
    <td style="white-space: nowrap; text-align: right">2.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">237.66 K</td>
    <td style="white-space: nowrap; text-align: right">2.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">236.36 K</td>
    <td style="white-space: nowrap; text-align: right">2.18x</td>
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
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap">3.37 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap">9.13 KB</td>
    <td>2.71x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap">12.27 KB</td>
    <td>3.65x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap">12.14 KB</td>
    <td>3.61x</td>
  </tr>
</table>



__Input: readproperty__

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
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap; text-align: right">529.73 K</td>
    <td style="white-space: nowrap; text-align: right">1.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;368.66%</td>
    <td style="white-space: nowrap; text-align: right">1.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">370.11 K</td>
    <td style="white-space: nowrap; text-align: right">2.70 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;272.40%</td>
    <td style="white-space: nowrap; text-align: right">2.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">6.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">336.29 K</td>
    <td style="white-space: nowrap; text-align: right">2.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;217.77%</td>
    <td style="white-space: nowrap; text-align: right">2.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">7.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">274.52 K</td>
    <td style="white-space: nowrap; text-align: right">3.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;169.03%</td>
    <td style="white-space: nowrap; text-align: right">3.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.63 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap;text-align: right">529.73 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">370.11 K</td>
    <td style="white-space: nowrap; text-align: right">1.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">336.29 K</td>
    <td style="white-space: nowrap; text-align: right">1.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">274.52 K</td>
    <td style="white-space: nowrap; text-align: right">1.93x</td>
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
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap">3.23 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap">5.70 KB</td>
    <td>1.76x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap">7.29 KB</td>
    <td>2.25x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap">10.56 KB</td>
    <td>3.27x</td>
  </tr>
</table>



__Input: writeproperty__

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
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap; text-align: right">503.15 K</td>
    <td style="white-space: nowrap; text-align: right">1.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;356.30%</td>
    <td style="white-space: nowrap; text-align: right">1.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">275.89 K</td>
    <td style="white-space: nowrap; text-align: right">3.62 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;148.53%</td>
    <td style="white-space: nowrap; text-align: right">3.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">253.38 K</td>
    <td style="white-space: nowrap; text-align: right">3.95 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;166.91%</td>
    <td style="white-space: nowrap; text-align: right">3.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">9.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">244.61 K</td>
    <td style="white-space: nowrap; text-align: right">4.09 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;126.19%</td>
    <td style="white-space: nowrap; text-align: right">3.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">9.96 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap;text-align: right">503.15 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap; text-align: right">275.89 K</td>
    <td style="white-space: nowrap; text-align: right">1.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">253.38 K</td>
    <td style="white-space: nowrap; text-align: right">1.99x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap; text-align: right">244.61 K</td>
    <td style="white-space: nowrap; text-align: right">2.06x</td>
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
    <td style="white-space: nowrap">map Form to Matter request</td>
    <td style="white-space: nowrap">3.38 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classified client failure</td>
    <td style="white-space: nowrap">11.20 KB</td>
    <td>3.31x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">controller Transport.request/3</td>
    <td style="white-space: nowrap">11.99 KB</td>
    <td>3.55x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">one-shot Transport.request/3</td>
    <td style="white-space: nowrap">9.53 KB</td>
    <td>2.82x</td>
  </tr>
</table>