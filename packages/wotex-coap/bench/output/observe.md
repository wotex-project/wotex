# Observe freshness and report admission

`Wotex.CoAP.Observe.fresh?/3` 24-bit serial arithmetic for an in-order
sequence, a wraparound and the 128-second escape, and
`Wotex.CoAP.Observation.Report` over notifications of 64 bytes, 512 bytes
and 16 KiB. `Report.new/2` validates the first datagram and decodes its
metadata; the completion job continues the representation with
`Wotex.CoAP.Blockwise.continue/5` against a pure in-process exchange
function (none for the single-datagram cases, 31 exchanges for 16 KiB in
512-byte blocks) and admits the body with `Report.complete/2`;
`Report.validate/1` rechecks a retained completed report.


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



__Input: 16 KiB blockwise report, 128 s escape__

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
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap; text-align: right">113654.75 K</td>
    <td style="white-space: nowrap; text-align: right">0.00880 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9000.92%</td>
    <td style="white-space: nowrap; text-align: right">0.00420 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.0166 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap; text-align: right">869.70 K</td>
    <td style="white-space: nowrap; text-align: right">1.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;662.72%</td>
    <td style="white-space: nowrap; text-align: right">0.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap; text-align: right">466.57 K</td>
    <td style="white-space: nowrap; text-align: right">2.14 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;452.59%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap; text-align: right">11.71 K</td>
    <td style="white-space: nowrap; text-align: right">85.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;39.01%</td>
    <td style="white-space: nowrap; text-align: right">85.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">162.32 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap;text-align: right">113654.75 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap; text-align: right">869.70 K</td>
    <td style="white-space: nowrap; text-align: right">130.68x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap; text-align: right">466.57 K</td>
    <td style="white-space: nowrap; text-align: right">243.6x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap; text-align: right">11.71 K</td>
    <td style="white-space: nowrap; text-align: right">9708.34x</td>
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
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap">0 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap">2.82 KB</td>
    <td>&mdash;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap">3.73 KB</td>
    <td>&mdash;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap">120.39 KB</td>
    <td>&mdash;</td>
  </tr>
</table>



__Input: 512-byte report, 24-bit wraparound__

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
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap; text-align: right">136.97 M</td>
    <td style="white-space: nowrap; text-align: right">0.00730 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2872.61%</td>
    <td style="white-space: nowrap; text-align: right">0.00830 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.0167 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap; text-align: right">1.45 M</td>
    <td style="white-space: nowrap; text-align: right">0.69 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;837.24%</td>
    <td style="white-space: nowrap; text-align: right">0.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap; text-align: right">0.73 M</td>
    <td style="white-space: nowrap; text-align: right">1.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;360.09%</td>
    <td style="white-space: nowrap; text-align: right">1.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap; text-align: right">0.41 M</td>
    <td style="white-space: nowrap; text-align: right">2.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;226.06%</td>
    <td style="white-space: nowrap; text-align: right">2.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.13 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap;text-align: right">136.97 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap; text-align: right">1.45 M</td>
    <td style="white-space: nowrap; text-align: right">94.46x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap; text-align: right">0.73 M</td>
    <td style="white-space: nowrap; text-align: right">187.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap; text-align: right">0.41 M</td>
    <td style="white-space: nowrap; text-align: right">337.35x</td>
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
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap">0 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap">2.02 KB</td>
    <td>&mdash;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap">2.88 KB</td>
    <td>&mdash;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap">6.79 KB</td>
    <td>&mdash;</td>
  </tr>
</table>



__Input: 64-byte report, in order__

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
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap; text-align: right">199.41 M</td>
    <td style="white-space: nowrap; text-align: right">0.00501 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;387.50%</td>
    <td style="white-space: nowrap; text-align: right">0.00500 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.00584 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap; text-align: right">1.39 M</td>
    <td style="white-space: nowrap; text-align: right">0.72 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;826.84%</td>
    <td style="white-space: nowrap; text-align: right">0.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap; text-align: right">0.83 M</td>
    <td style="white-space: nowrap; text-align: right">1.20 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;318.98%</td>
    <td style="white-space: nowrap; text-align: right">1.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.71 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap; text-align: right">0.42 M</td>
    <td style="white-space: nowrap; text-align: right">2.36 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;264.74%</td>
    <td style="white-space: nowrap; text-align: right">2.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.25 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap;text-align: right">199.41 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap; text-align: right">1.39 M</td>
    <td style="white-space: nowrap; text-align: right">143.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap; text-align: right">0.83 M</td>
    <td style="white-space: nowrap; text-align: right">239.84x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap; text-align: right">0.42 M</td>
    <td style="white-space: nowrap; text-align: right">470.16x</td>
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
    <td style="white-space: nowrap">decide freshness</td>
    <td style="white-space: nowrap">0 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate first report</td>
    <td style="white-space: nowrap">2.02 KB</td>
    <td>&mdash;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">revalidate completed report</td>
    <td style="white-space: nowrap">2.88 KB</td>
    <td>&mdash;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">continue and complete body</td>
    <td style="white-space: nowrap">6.79 KB</td>
    <td>&mdash;</td>
  </tr>
</table>