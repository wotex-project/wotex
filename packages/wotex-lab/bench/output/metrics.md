# Metrics collection, snapshots and export encodings

The Lab's metrics path from telemetry to the wire over workloads of 8,
64 and 512 request spans. The spans run over the runtime, HTTP and MQTT
transports with 21 actions and eight results (504 distinct label sets),
so the larger workloads fill more series: the snapshots hold 16,
88 and 528 series. Each scenario places a
`Wotex.Lab.Metrics.Collector` with a series budget of 1,024 under a Lab
instance and records its workload once before the measurement; nothing
is dropped or rejected.

`record spans into the collector` runs every span through
`Wotex.Lab.Telemetry.span/4`: metadata allowlisting, the start and stop
events and the collector's handler, which maps the outcome, action,
profile and component to closed label values and updates the counter
and histogram rows in its ETS table. `snapshot the collector` is
`Wotex.Lab.Metrics.Collector.snapshot/1`, an admitted and sorted
`Wotex.Lab.Metrics.Snapshot`. `render exposition text` and
`parse exposition text` are `Wotex.Lab.Metrics.Exposition.render/1` and
`Wotex.Lab.Metrics.Exposition.parse/2`, the self-scraper's Prometheus
text format; the parse must return the rendered snapshot's series.
`encode remote write` is
`Wotex.Lab.Metrics.RemoteWrite.encode/2`: the hand-written
`prometheus.WriteRequest` protobuf compressed by the Lab's own Snappy
block encoder. Every job compares its result with the value computed
before the run. Memory is that of the calling process: the collector
builds its snapshot in its own process, so that job's memory column
shows little more than the reply.


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



__Input: 512 spans__

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
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap; text-align: right">780.13</td>
    <td style="white-space: nowrap; text-align: right">1.28 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.14%</td>
    <td style="white-space: nowrap; text-align: right">1.28 ms</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap; text-align: right">481.31</td>
    <td style="white-space: nowrap; text-align: right">2.08 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.54%</td>
    <td style="white-space: nowrap; text-align: right">2.04 ms</td>
    <td style="white-space: nowrap; text-align: right">2.31 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap; text-align: right">395.12</td>
    <td style="white-space: nowrap; text-align: right">2.53 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.47%</td>
    <td style="white-space: nowrap; text-align: right">2.54 ms</td>
    <td style="white-space: nowrap; text-align: right">2.71 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap; text-align: right">302.59</td>
    <td style="white-space: nowrap; text-align: right">3.30 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.82%</td>
    <td style="white-space: nowrap; text-align: right">3.30 ms</td>
    <td style="white-space: nowrap; text-align: right">3.48 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap; text-align: right">180.22</td>
    <td style="white-space: nowrap; text-align: right">5.55 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.26%</td>
    <td style="white-space: nowrap; text-align: right">5.53 ms</td>
    <td style="white-space: nowrap; text-align: right">5.95 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap;text-align: right">780.13</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap; text-align: right">481.31</td>
    <td style="white-space: nowrap; text-align: right">1.62x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap; text-align: right">395.12</td>
    <td style="white-space: nowrap; text-align: right">1.97x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap; text-align: right">302.59</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap; text-align: right">180.22</td>
    <td style="white-space: nowrap; text-align: right">4.33x</td>
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
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap">1.22 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap">0.00012 MB</td>
    <td>0.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap">5.18 MB</td>
    <td>4.23x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap">18.52 MB</td>
    <td>15.12x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap">7.88 MB</td>
    <td>6.43x</td>
  </tr>
</table>



__Input: 64 spans__

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
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap; text-align: right">2.83 K</td>
    <td style="white-space: nowrap; text-align: right">353.81 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.03%</td>
    <td style="white-space: nowrap; text-align: right">352.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">396.61 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap; text-align: right">2.13 K</td>
    <td style="white-space: nowrap; text-align: right">468.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.17%</td>
    <td style="white-space: nowrap; text-align: right">465.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">501.00 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap; text-align: right">1.87 K</td>
    <td style="white-space: nowrap; text-align: right">533.60 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.00%</td>
    <td style="white-space: nowrap; text-align: right">527.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">618.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap; text-align: right">0.94 K</td>
    <td style="white-space: nowrap; text-align: right">1061.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.40%</td>
    <td style="white-space: nowrap; text-align: right">1061.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1179.62 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap; text-align: right">0.53 K</td>
    <td style="white-space: nowrap; text-align: right">1891.51 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.39%</td>
    <td style="white-space: nowrap; text-align: right">1889.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2048.01 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap;text-align: right">2.83 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap; text-align: right">2.13 K</td>
    <td style="white-space: nowrap; text-align: right">1.32x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap; text-align: right">1.87 K</td>
    <td style="white-space: nowrap; text-align: right">1.51x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap; text-align: right">0.94 K</td>
    <td style="white-space: nowrap; text-align: right">3.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap; text-align: right">0.53 K</td>
    <td style="white-space: nowrap; text-align: right">5.35x</td>
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
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap">0.00012 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap">2.26 MB</td>
    <td>18546.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap">0.53 MB</td>
    <td>4313.38x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap">2.11 MB</td>
    <td>17267.19x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap">2.94 MB</td>
    <td>24079.13x</td>
  </tr>
</table>



__Input: 8 spans__

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
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap; text-align: right">18.58 K</td>
    <td style="white-space: nowrap; text-align: right">53.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.84%</td>
    <td style="white-space: nowrap; text-align: right">50.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">66.71 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap; text-align: right">15.91 K</td>
    <td style="white-space: nowrap; text-align: right">62.86 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.59%</td>
    <td style="white-space: nowrap; text-align: right">61.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">78.00 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap; text-align: right">6.59 K</td>
    <td style="white-space: nowrap; text-align: right">151.65 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.32%</td>
    <td style="white-space: nowrap; text-align: right">148.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">233.39 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap; text-align: right">2.97 K</td>
    <td style="white-space: nowrap; text-align: right">336.26 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.28%</td>
    <td style="white-space: nowrap; text-align: right">323.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">442.16 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap; text-align: right">2.08 K</td>
    <td style="white-space: nowrap; text-align: right">481.16 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.02%</td>
    <td style="white-space: nowrap; text-align: right">475.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">552.71 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap;text-align: right">18.58 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap; text-align: right">15.91 K</td>
    <td style="white-space: nowrap; text-align: right">1.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap; text-align: right">6.59 K</td>
    <td style="white-space: nowrap; text-align: right">2.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap; text-align: right">2.97 K</td>
    <td style="white-space: nowrap; text-align: right">6.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap; text-align: right">2.08 K</td>
    <td style="white-space: nowrap; text-align: right">8.94x</td>
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
    <td style="white-space: nowrap">record spans into the collector</td>
    <td style="white-space: nowrap">203.06 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">snapshot the collector</td>
    <td style="white-space: nowrap">10.94 KB</td>
    <td>0.05x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">render exposition text</td>
    <td style="white-space: nowrap">158.42 KB</td>
    <td>0.78x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode remote write</td>
    <td style="white-space: nowrap">667.21 KB</td>
    <td>3.29x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse exposition text</td>
    <td style="white-space: nowrap">841.95 KB</td>
    <td>4.15x</td>
  </tr>
</table>