# Matter bridge endpoint custody microbenchmarks

Pure endpoint identity operations and 256-device restart validation; no native server or controller peer.

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
    <td style="white-space: nowrap">repeat existing identity</td>
    <td style="white-space: nowrap; text-align: right">25.70 M</td>
    <td style="white-space: nowrap; text-align: right">38.92 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9260.60%</td>
    <td style="white-space: nowrap; text-align: right">41 ns</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">allocate one stable endpoint</td>
    <td style="white-space: nowrap; text-align: right">17.98 M</td>
    <td style="white-space: nowrap; text-align: right">55.63 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6814.62%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate 256-endpoint restart snapshot</td>
    <td style="white-space: nowrap; text-align: right">0.0169 M</td>
    <td style="white-space: nowrap; text-align: right">59211.72 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.76%</td>
    <td style="white-space: nowrap; text-align: right">58291 ns</td>
    <td style="white-space: nowrap; text-align: right">73583 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">repeat existing identity</td>
    <td style="white-space: nowrap;text-align: right">25.70 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">allocate one stable endpoint</td>
    <td style="white-space: nowrap; text-align: right">17.98 M</td>
    <td style="white-space: nowrap; text-align: right">1.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate 256-endpoint restart snapshot</td>
    <td style="white-space: nowrap; text-align: right">0.0169 M</td>
    <td style="white-space: nowrap; text-align: right">1521.49x</td>
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
    <td style="white-space: nowrap">repeat existing identity</td>
    <td style="white-space: nowrap">32 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">allocate one stable endpoint</td>
    <td style="white-space: nowrap">208 B</td>
    <td>6.5x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate 256-endpoint restart snapshot</td>
    <td style="white-space: nowrap">156960 B</td>
    <td>4905.0x</td>
  </tr>
</table>