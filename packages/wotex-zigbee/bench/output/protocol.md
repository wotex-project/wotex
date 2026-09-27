# Wotex Zigbee protocol microbenchmarks

Pure framing, ZDO response decoding, ZCL request encoding and AF request validation on the development host; no serial device or radio.

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
    <td style="white-space: nowrap">decode ZDO active endpoints</td>
    <td style="white-space: nowrap; text-align: right">20.37 M</td>
    <td style="white-space: nowrap; text-align: right">49.08 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7613.96%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate AF data request</td>
    <td style="white-space: nowrap; text-align: right">14.65 M</td>
    <td style="white-space: nowrap; text-align: right">68.24 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3848.51%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ZCL attribute read</td>
    <td style="white-space: nowrap; text-align: right">4.82 M</td>
    <td style="white-space: nowrap; text-align: right">207.64 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4661.24%</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
    <td style="white-space: nowrap; text-align: right">333 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse 64-byte NCP indication</td>
    <td style="white-space: nowrap; text-align: right">1.80 M</td>
    <td style="white-space: nowrap; text-align: right">555.66 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;911.49%</td>
    <td style="white-space: nowrap; text-align: right">417 ns</td>
    <td style="white-space: nowrap; text-align: right">792 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode ZDO active endpoints</td>
    <td style="white-space: nowrap;text-align: right">20.37 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate AF data request</td>
    <td style="white-space: nowrap; text-align: right">14.65 M</td>
    <td style="white-space: nowrap; text-align: right">1.39x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ZCL attribute read</td>
    <td style="white-space: nowrap; text-align: right">4.82 M</td>
    <td style="white-space: nowrap; text-align: right">4.23x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse 64-byte NCP indication</td>
    <td style="white-space: nowrap; text-align: right">1.80 M</td>
    <td style="white-space: nowrap; text-align: right">11.32x</td>
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
    <td style="white-space: nowrap">decode ZDO active endpoints</td>
    <td style="white-space: nowrap">192 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate AF data request</td>
    <td style="white-space: nowrap">40 B</td>
    <td>0.21x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ZCL attribute read</td>
    <td style="white-space: nowrap">280 B</td>
    <td>1.46x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse 64-byte NCP indication</td>
    <td style="white-space: nowrap">1480 B</td>
    <td>7.71x</td>
  </tr>
</table>