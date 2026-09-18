# Lifecycle replay

Replays a recorded lifecycle of 6, 60 and 600 changes from `staged` with
`WotexContinuum.Lifecycle.transition/4`, one `DateTime` per second through
the cycle `ready`, `active`, `degraded`, `active`, `draining`, `stopped`.
Every step revalidates the current value, admits only an edge of the
transition graph, checks that time does not decrease and increments the
generation.


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



__Input: 6 transitions__

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
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap; text-align: right">86.83 K</td>
    <td style="white-space: nowrap; text-align: right">11.52 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.28%</td>
    <td style="white-space: nowrap; text-align: right">11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">17.67 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap;text-align: right">86.83 K</td>
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
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap">43.30 KB</td>
    <td>&nbsp;</td>
  </tr>
</table>



__Input: 60 transitions__

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
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap; text-align: right">8.67 K</td>
    <td style="white-space: nowrap; text-align: right">115.40 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.22%</td>
    <td style="white-space: nowrap; text-align: right">114.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">135.04 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap;text-align: right">8.67 K</td>
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
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap">431.44 KB</td>
    <td>&nbsp;</td>
  </tr>
</table>



__Input: 600 transitions__

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
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap; text-align: right">878.38</td>
    <td style="white-space: nowrap; text-align: right">1.14 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.03%</td>
    <td style="white-space: nowrap; text-align: right">1.14 ms</td>
    <td style="white-space: nowrap; text-align: right">1.21 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap;text-align: right">878.38</td>
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
    <td style="white-space: nowrap">replay with transition/4</td>
    <td style="white-space: nowrap">4.23 MB</td>
    <td>&nbsp;</td>
  </tr>
</table>