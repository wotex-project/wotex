# Runner evaluation with an in-memory target

`Wotex.Conformance.Runner.run/4` over the corpora of the corpus benchmark
with a `{module, state}` target that replays each vector's expected
observation through `Wotex.Conformance.Target.Response.from_map/2`. A run
verifies a 64 KiB subject archive, builds each expectation-free target
request, validates and digests every observation, classifies it and
builds the report. Selecting one vector records the others as
`not_run`. No external target process is started, so the figures
exclude process start-up and the target protocol's JSON transfer.


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
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap; text-align: right">3.20 K</td>
    <td style="white-space: nowrap; text-align: right">312.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.17%</td>
    <td style="white-space: nowrap; text-align: right">309.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">397.43 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap; text-align: right">2.40 K</td>
    <td style="white-space: nowrap; text-align: right">416.01 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.63%</td>
    <td style="white-space: nowrap; text-align: right">410 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">553.04 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap;text-align: right">3.20 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap; text-align: right">2.40 K</td>
    <td style="white-space: nowrap; text-align: right">1.33x</td>
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
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap">391.31 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap">645.05 KB</td>
    <td>1.65x</td>
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
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap; text-align: right">1.31 K</td>
    <td style="white-space: nowrap; text-align: right">0.76 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.58%</td>
    <td style="white-space: nowrap; text-align: right">0.75 ms</td>
    <td style="white-space: nowrap; text-align: right">1.09 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap; text-align: right">0.81 K</td>
    <td style="white-space: nowrap; text-align: right">1.23 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.44%</td>
    <td style="white-space: nowrap; text-align: right">1.20 ms</td>
    <td style="white-space: nowrap; text-align: right">1.58 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap;text-align: right">1.31 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap; text-align: right">0.81 K</td>
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
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap">1.33 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap">2.40 MB</td>
    <td>1.81x</td>
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
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap; text-align: right">746.84</td>
    <td style="white-space: nowrap; text-align: right">1.34 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.28%</td>
    <td style="white-space: nowrap; text-align: right">1.31 ms</td>
    <td style="white-space: nowrap; text-align: right">1.87 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap; text-align: right">446.32</td>
    <td style="white-space: nowrap; text-align: right">2.24 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.26%</td>
    <td style="white-space: nowrap; text-align: right">2.19 ms</td>
    <td style="white-space: nowrap; text-align: right">2.73 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap;text-align: right">746.84</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap; text-align: right">446.32</td>
    <td style="white-space: nowrap; text-align: right">1.67x</td>
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
    <td style="white-space: nowrap">run one selected vector</td>
    <td style="white-space: nowrap">2.59 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">run every vector</td>
    <td style="white-space: nowrap">4.75 MB</td>
    <td>1.84x</td>
  </tr>
</table>