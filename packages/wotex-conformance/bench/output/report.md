# Result classification and canonical report digests

Evidence construction for 16, 64 and 128 passing vectors of the corpus
benchmark. Classification builds one `Wotex.Conformance.Result` per vector,
digesting its observation and its evidence. `Wotex.Conformance.Report.new/5`
validates the environment, sorts the results and derives the run
identifier and report digest; encoding emits the canonical JSON form, and
verification recomputes the report digest from its canonical map.


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



__Input: 16 vectors__

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
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap; text-align: right">14.47 K</td>
    <td style="white-space: nowrap; text-align: right">69.10 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.45%</td>
    <td style="white-space: nowrap; text-align: right">68.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">88.20 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap; text-align: right">14.37 K</td>
    <td style="white-space: nowrap; text-align: right">69.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.54%</td>
    <td style="white-space: nowrap; text-align: right">69.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">84.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap; text-align: right">12.59 K</td>
    <td style="white-space: nowrap; text-align: right">79.43 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.86%</td>
    <td style="white-space: nowrap; text-align: right">79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">98.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap; text-align: right">9.01 K</td>
    <td style="white-space: nowrap; text-align: right">110.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.70%</td>
    <td style="white-space: nowrap; text-align: right">109.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">134.13 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap;text-align: right">14.47 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap; text-align: right">14.37 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap; text-align: right">12.59 K</td>
    <td style="white-space: nowrap; text-align: right">1.15x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap; text-align: right">9.01 K</td>
    <td style="white-space: nowrap; text-align: right">1.61x</td>
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
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap">176.57 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap">177.59 KB</td>
    <td>1.01x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap">193.15 KB</td>
    <td>1.09x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap">271.50 KB</td>
    <td>1.54x</td>
  </tr>
</table>



__Input: 64 vectors__

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
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap; text-align: right">3.40 K</td>
    <td style="white-space: nowrap; text-align: right">294.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.71%</td>
    <td style="white-space: nowrap; text-align: right">290.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">474.43 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap; text-align: right">3.24 K</td>
    <td style="white-space: nowrap; text-align: right">309.03 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.46%</td>
    <td style="white-space: nowrap; text-align: right">301.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">546.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap; text-align: right">3.23 K</td>
    <td style="white-space: nowrap; text-align: right">309.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.72%</td>
    <td style="white-space: nowrap; text-align: right">305.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">512.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap; text-align: right">2.20 K</td>
    <td style="white-space: nowrap; text-align: right">455.26 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.54%</td>
    <td style="white-space: nowrap; text-align: right">446.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">770.61 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap;text-align: right">3.40 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap; text-align: right">3.24 K</td>
    <td style="white-space: nowrap; text-align: right">1.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap; text-align: right">3.23 K</td>
    <td style="white-space: nowrap; text-align: right">1.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap; text-align: right">2.20 K</td>
    <td style="white-space: nowrap; text-align: right">1.55x</td>
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
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap">657.50 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap">683.09 KB</td>
    <td>1.04x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap">656.78 KB</td>
    <td>1.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap">1086 KB</td>
    <td>1.65x</td>
  </tr>
</table>



__Input: 128 vectors__

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
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap; text-align: right">1.61 K</td>
    <td style="white-space: nowrap; text-align: right">620.31 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.70%</td>
    <td style="white-space: nowrap; text-align: right">593.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">914.44 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap; text-align: right">1.60 K</td>
    <td style="white-space: nowrap; text-align: right">624.10 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.05%</td>
    <td style="white-space: nowrap; text-align: right">605.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">992.14 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap; text-align: right">1.47 K</td>
    <td style="white-space: nowrap; text-align: right">679.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;27.97%</td>
    <td style="white-space: nowrap; text-align: right">571.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1210.74 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap; text-align: right">1.09 K</td>
    <td style="white-space: nowrap; text-align: right">916.18 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.00%</td>
    <td style="white-space: nowrap; text-align: right">895.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1430.69 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap;text-align: right">1.61 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap; text-align: right">1.60 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap; text-align: right">1.47 K</td>
    <td style="white-space: nowrap; text-align: right">1.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap; text-align: right">1.09 K</td>
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
    <td style="white-space: nowrap">verify report digest</td>
    <td style="white-space: nowrap">1.27 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">build report</td>
    <td style="white-space: nowrap">1.30 MB</td>
    <td>1.03x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode canonical report</td>
    <td style="white-space: nowrap">1.27 MB</td>
    <td>1.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classify results</td>
    <td style="white-space: nowrap">2.12 MB</td>
    <td>1.67x</td>
  </tr>
</table>