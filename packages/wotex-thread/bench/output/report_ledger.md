# Thread native report credit ledger

`Wotex.Thread.OpenThread.ReportLedger`, the BEAM side of the native State
report credit: `register/5` admits each transmitted report in sequence
under the per-stream and per-session frame and byte bounds, `consume/4`
records the stream owner's delivery admission with its token, and
`advance/1` proposes the contiguous cumulative acknowledgement. Windows
hold 1 report, 16 reports on one stream (the per-stream limit) and 64
reports over four streams (the session frame limit), each of 212 encoded
bytes.


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



__Input: 1 report on 1 stream__

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
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap; text-align: right">17.66 M</td>
    <td style="white-space: nowrap; text-align: right">56.62 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1506.59%</td>
    <td style="white-space: nowrap; text-align: right">50 ns</td>
    <td style="white-space: nowrap; text-align: right">70.90 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap; text-align: right">9.16 M</td>
    <td style="white-space: nowrap; text-align: right">109.20 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5323.19%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap; text-align: right">8.78 M</td>
    <td style="white-space: nowrap; text-align: right">113.94 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4527.78%</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap;text-align: right">17.66 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap; text-align: right">9.16 M</td>
    <td style="white-space: nowrap; text-align: right">1.93x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap; text-align: right">8.78 M</td>
    <td style="white-space: nowrap; text-align: right">2.01x</td>
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
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap">312 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap">312 B</td>
    <td>1.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap">272 B</td>
    <td>0.87x</td>
  </tr>
</table>



__Input: 16 reports on 1 stream__

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
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap; text-align: right">1013.30 K</td>
    <td style="white-space: nowrap; text-align: right">0.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;437.66%</td>
    <td style="white-space: nowrap; text-align: right">0.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap; text-align: right">871.49 K</td>
    <td style="white-space: nowrap; text-align: right">1.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;380.09%</td>
    <td style="white-space: nowrap; text-align: right">1.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap; text-align: right">716.23 K</td>
    <td style="white-space: nowrap; text-align: right">1.40 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;317.43%</td>
    <td style="white-space: nowrap; text-align: right">1.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.92 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap;text-align: right">1013.30 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap; text-align: right">871.49 K</td>
    <td style="white-space: nowrap; text-align: right">1.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap; text-align: right">716.23 K</td>
    <td style="white-space: nowrap; text-align: right">1.41x</td>
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
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap">6.75 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap">5.04 KB</td>
    <td>0.75x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap">6.87 KB</td>
    <td>1.02x</td>
  </tr>
</table>



__Input: 64 reports on 4 streams__

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
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap; text-align: right">176.21 K</td>
    <td style="white-space: nowrap; text-align: right">5.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;48.09%</td>
    <td style="white-space: nowrap; text-align: right">5.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">10.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap; text-align: right">133.11 K</td>
    <td style="white-space: nowrap; text-align: right">7.51 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.35%</td>
    <td style="white-space: nowrap; text-align: right">7.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">9.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap; text-align: right">118.85 K</td>
    <td style="white-space: nowrap; text-align: right">8.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.35%</td>
    <td style="white-space: nowrap; text-align: right">8.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">14.96 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap;text-align: right">176.21 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap; text-align: right">133.11 K</td>
    <td style="white-space: nowrap; text-align: right">1.32x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap; text-align: right">118.85 K</td>
    <td style="white-space: nowrap; text-align: right">1.48x</td>
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
    <td style="white-space: nowrap">admit delivery of every report</td>
    <td style="white-space: nowrap">30.50 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">propose cumulative acknowledgement</td>
    <td style="white-space: nowrap">27.34 KB</td>
    <td>0.9x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">register transmitted reports</td>
    <td style="white-space: nowrap">34.30 KB</td>
    <td>1.12x</td>
  </tr>
</table>