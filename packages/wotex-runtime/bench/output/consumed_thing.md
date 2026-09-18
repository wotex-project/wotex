# ConsumedThing construction and short operations

`Wotex.Runtime.ConsumedThing` over synthetic Thing Descriptions with one, 24
and 240 Properties, one Action and one Event, each with a single relative
`https` Form. Construction includes Thing Description validation. The short
operations run the full caller-side path (Form and binding-profile selection
against two profiles, request construction, credential resolution, port
isolation, the `[:wotex, :runtime, :request]` telemetry span and Result
validation) through an in-process transport that answers at once, so no
protocol exchange is measured.


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



__Input: 1 Property__

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
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap; text-align: right">22.64 K</td>
    <td style="white-space: nowrap; text-align: right">44.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.47%</td>
    <td style="white-space: nowrap; text-align: right">43.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">56.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap; text-align: right">21.70 K</td>
    <td style="white-space: nowrap; text-align: right">46.09 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.74%</td>
    <td style="white-space: nowrap; text-align: right">45.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">59.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap; text-align: right">18.51 K</td>
    <td style="white-space: nowrap; text-align: right">54.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.72%</td>
    <td style="white-space: nowrap; text-align: right">53.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">66.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap; text-align: right">15.73 K</td>
    <td style="white-space: nowrap; text-align: right">63.59 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.29%</td>
    <td style="white-space: nowrap; text-align: right">63.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">76.86 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap;text-align: right">22.64 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap; text-align: right">21.70 K</td>
    <td style="white-space: nowrap; text-align: right">1.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap; text-align: right">18.51 K</td>
    <td style="white-space: nowrap; text-align: right">1.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap; text-align: right">15.73 K</td>
    <td style="white-space: nowrap; text-align: right">1.44x</td>
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
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap">67.86 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap">71.35 KB</td>
    <td>1.05x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap">129.89 KB</td>
    <td>1.91x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap">93.10 KB</td>
    <td>1.37x</td>
  </tr>
</table>



__Input: 24 Properties__

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
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap; text-align: right">22.04 K</td>
    <td style="white-space: nowrap; text-align: right">45.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.71%</td>
    <td style="white-space: nowrap; text-align: right">44.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">60.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap; text-align: right">21.36 K</td>
    <td style="white-space: nowrap; text-align: right">46.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.05%</td>
    <td style="white-space: nowrap; text-align: right">45.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">62.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap; text-align: right">16.75 K</td>
    <td style="white-space: nowrap; text-align: right">59.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.15%</td>
    <td style="white-space: nowrap; text-align: right">58.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">75.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap; text-align: right">4.26 K</td>
    <td style="white-space: nowrap; text-align: right">234.86 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.12%</td>
    <td style="white-space: nowrap; text-align: right">234.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">279.18 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap;text-align: right">22.04 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap; text-align: right">21.36 K</td>
    <td style="white-space: nowrap; text-align: right">1.03x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap; text-align: right">16.75 K</td>
    <td style="white-space: nowrap; text-align: right">1.32x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap; text-align: right">4.26 K</td>
    <td style="white-space: nowrap; text-align: right">5.18x</td>
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
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap">68.07 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap">71.33 KB</td>
    <td>1.05x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap">95.82 KB</td>
    <td>1.41x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap">581.89 KB</td>
    <td>8.55x</td>
  </tr>
</table>



__Input: 240 Properties__

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
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap; text-align: right">21.94 K</td>
    <td style="white-space: nowrap; text-align: right">45.59 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.39%</td>
    <td style="white-space: nowrap; text-align: right">44.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">59.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap; text-align: right">21.74 K</td>
    <td style="white-space: nowrap; text-align: right">46.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.41%</td>
    <td style="white-space: nowrap; text-align: right">45.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">60.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap; text-align: right">15.33 K</td>
    <td style="white-space: nowrap; text-align: right">65.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.85%</td>
    <td style="white-space: nowrap; text-align: right">66.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">79.40 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap; text-align: right">0.52 K</td>
    <td style="white-space: nowrap; text-align: right">1907.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.17%</td>
    <td style="white-space: nowrap; text-align: right">1904.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2075.34 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap;text-align: right">21.94 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap; text-align: right">21.74 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap; text-align: right">15.33 K</td>
    <td style="white-space: nowrap; text-align: right">1.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap; text-align: right">0.52 K</td>
    <td style="white-space: nowrap; text-align: right">41.85x</td>
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
    <td style="white-space: nowrap">invoke_action</td>
    <td style="white-space: nowrap">68.07 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">read_property</td>
    <td style="white-space: nowrap">71.63 KB</td>
    <td>1.05x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">read_multiple_properties (every Property)</td>
    <td style="white-space: nowrap">117.76 KB</td>
    <td>1.73x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new (validates the Thing Description)</td>
    <td style="white-space: nowrap">4831.31 KB</td>
    <td>70.98x</td>
  </tr>
</table>