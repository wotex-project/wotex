# Thread ot-daemon response parsing

`Wotex.Thread.Daemon.parse/2` over the four read commands of the
`ot-daemon` client: each complete response carries the command echo, one
value line, `Done` and the next prompt with CRLF line endings; the
incomplete response stops before `Done` and must yield `:more`. Parsing
checks UTF-8, strips the echo and prompt, rejects remote errors and types
the value (the RLOC16 as an integer).


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



__Input: network name__

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
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap; text-align: right">622.58 K</td>
    <td style="white-space: nowrap; text-align: right">1.61 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;919.39%</td>
    <td style="white-space: nowrap; text-align: right">1.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap; text-align: right">531.47 K</td>
    <td style="white-space: nowrap; text-align: right">1.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1043.87%</td>
    <td style="white-space: nowrap; text-align: right">1.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.63 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap;text-align: right">622.58 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap; text-align: right">531.47 K</td>
    <td style="white-space: nowrap; text-align: right">1.17x</td>
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
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap">0.77 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap">1.08 KB</td>
    <td>1.39x</td>
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
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap; text-align: right">575.50 K</td>
    <td style="white-space: nowrap; text-align: right">1.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1217.54%</td>
    <td style="white-space: nowrap; text-align: right">1.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap; text-align: right">517.95 K</td>
    <td style="white-space: nowrap; text-align: right">1.93 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;987.78%</td>
    <td style="white-space: nowrap; text-align: right">1.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.04 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap;text-align: right">575.50 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap; text-align: right">517.95 K</td>
    <td style="white-space: nowrap; text-align: right">1.11x</td>
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
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap">0.74 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap">1.09 KB</td>
    <td>1.46x</td>
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
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap; text-align: right">747.32 K</td>
    <td style="white-space: nowrap; text-align: right">1.34 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1122.14%</td>
    <td style="white-space: nowrap; text-align: right">0.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap; text-align: right">566.36 K</td>
    <td style="white-space: nowrap; text-align: right">1.77 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1204.80%</td>
    <td style="white-space: nowrap; text-align: right">1.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.67 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap;text-align: right">747.32 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap; text-align: right">566.36 K</td>
    <td style="white-space: nowrap; text-align: right">1.32x</td>
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
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap">824 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap">760 B</td>
    <td>0.92x</td>
  </tr>
</table>



__Input: version__

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
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap; text-align: right">545.42 K</td>
    <td style="white-space: nowrap; text-align: right">1.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1201.81%</td>
    <td style="white-space: nowrap; text-align: right">1.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap; text-align: right">512.27 K</td>
    <td style="white-space: nowrap; text-align: right">1.95 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;985.59%</td>
    <td style="white-space: nowrap; text-align: right">1.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap;text-align: right">545.42 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap; text-align: right">512.27 K</td>
    <td style="white-space: nowrap; text-align: right">1.06x</td>
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
    <td style="white-space: nowrap">detect incomplete response</td>
    <td style="white-space: nowrap">0.77 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse complete response</td>
    <td style="white-space: nowrap">1.07 KB</td>
    <td>1.4x</td>
  </tr>
</table>