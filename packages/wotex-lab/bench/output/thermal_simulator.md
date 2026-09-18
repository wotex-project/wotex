# Thermal simulator

`Wotex.Lab.Simulators.Thermal.generate/1`, the deterministic first-order
room temperature simulator that supplies the synthetic observations of
the Nx lanes, with a step of 60,000 and the default 32 samples, 512
samples and the 4,096-sample maximum. The heater schedule adds 0.5 °C at
every 16th sample (256 entries at the maximum, the schedule bound) and
every 64th sample from index 7 is a glitch reported with `:bad` quality.

`admit and simulate` validates every option and schedule entry, then
runs the model with its seeded linear congruential noise and returns
the samples and the manifest. `admit and reject` passes the same
options with one glitch index past the last sample: admission checks
every entry and returns `:invalid_simulation`, which isolates the cost
of admission. No Nx tensor is built.


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



__Input: 32 samples__

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
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap; text-align: right">2.13 M</td>
    <td style="white-space: nowrap; text-align: right">0.47 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;878.69%</td>
    <td style="white-space: nowrap; text-align: right">0.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap; text-align: right">0.20 M</td>
    <td style="white-space: nowrap; text-align: right">4.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;63.39%</td>
    <td style="white-space: nowrap; text-align: right">4.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">6.67 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap;text-align: right">2.13 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap; text-align: right">0.20 M</td>
    <td style="white-space: nowrap; text-align: right">10.49x</td>
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
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap">1.70 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap">8.62 KB</td>
    <td>5.06x</td>
  </tr>
</table>



__Input: 4096 samples__

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
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap; text-align: right">83.08 K</td>
    <td style="white-space: nowrap; text-align: right">12.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.64%</td>
    <td style="white-space: nowrap; text-align: right">11.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">14.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap; text-align: right">1.13 K</td>
    <td style="white-space: nowrap; text-align: right">886.12 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.81%</td>
    <td style="white-space: nowrap; text-align: right">870.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1041.49 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap;text-align: right">83.08 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap; text-align: right">1.13 K</td>
    <td style="white-space: nowrap; text-align: right">73.62x</td>
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
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap">43.41 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap">893.04 KB</td>
    <td>20.57x</td>
  </tr>
</table>



__Input: 512 samples__

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
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap; text-align: right">665.10 K</td>
    <td style="white-space: nowrap; text-align: right">1.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;290.74%</td>
    <td style="white-space: nowrap; text-align: right">1.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap; text-align: right">12.07 K</td>
    <td style="white-space: nowrap; text-align: right">82.86 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.73%</td>
    <td style="white-space: nowrap; text-align: right">81.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">111.81 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap;text-align: right">665.10 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap; text-align: right">12.07 K</td>
    <td style="white-space: nowrap; text-align: right">55.11x</td>
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
    <td style="white-space: nowrap">admit and reject</td>
    <td style="white-space: nowrap">5.41 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit and simulate</td>
    <td style="white-space: nowrap">113.61 KB</td>
    <td>21.01x</td>
  </tr>
</table>