# Corpus loading and digest verification

`Wotex.Conformance.Corpus.load/1` reads a corpus directory, checks its
declared files, decodes and constructs every vector and compares each
vector digest and the aggregate digest with the manifest.
`Wotex.Conformance.Corpus.from_map/1` constructs the same corpus from
already decoded vectors, and the digest job recomputes the canonical
corpus digest alone. The 16-vector input is the bundled Thing
Description 1.1 corpus; the larger inputs repeat its vectors under new
identifiers and are written to a temporary directory before measurement.


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
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap; text-align: right">4.30 K</td>
    <td style="white-space: nowrap; text-align: right">232.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.61%</td>
    <td style="white-space: nowrap; text-align: right">231.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">388.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap; text-align: right">1.30 K</td>
    <td style="white-space: nowrap; text-align: right">770.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.95%</td>
    <td style="white-space: nowrap; text-align: right">762.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1009.05 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap; text-align: right">0.54 K</td>
    <td style="white-space: nowrap; text-align: right">1867.28 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.92%</td>
    <td style="white-space: nowrap; text-align: right">1852.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2083.32 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap;text-align: right">4.30 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap; text-align: right">1.30 K</td>
    <td style="white-space: nowrap; text-align: right">3.32x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap; text-align: right">0.54 K</td>
    <td style="white-space: nowrap; text-align: right">8.03x</td>
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
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap">0.62 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap">1.69 MB</td>
    <td>2.73x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap">1.85 MB</td>
    <td>2.99x</td>
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
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap; text-align: right">948.69</td>
    <td style="white-space: nowrap; text-align: right">1.05 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.47%</td>
    <td style="white-space: nowrap; text-align: right">0.99 ms</td>
    <td style="white-space: nowrap; text-align: right">1.30 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap; text-align: right">296.44</td>
    <td style="white-space: nowrap; text-align: right">3.37 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.57%</td>
    <td style="white-space: nowrap; text-align: right">3.31 ms</td>
    <td style="white-space: nowrap; text-align: right">3.86 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap; text-align: right">137.52</td>
    <td style="white-space: nowrap; text-align: right">7.27 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.55%</td>
    <td style="white-space: nowrap; text-align: right">7.20 ms</td>
    <td style="white-space: nowrap; text-align: right">7.95 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap;text-align: right">948.69</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap; text-align: right">296.44</td>
    <td style="white-space: nowrap; text-align: right">3.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap; text-align: right">137.52</td>
    <td style="white-space: nowrap; text-align: right">6.9x</td>
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
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap">2.46 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap">6.74 MB</td>
    <td>2.74x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap">7.38 MB</td>
    <td>3.0x</td>
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
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap; text-align: right">495.10</td>
    <td style="white-space: nowrap; text-align: right">2.02 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.26%</td>
    <td style="white-space: nowrap; text-align: right">1.89 ms</td>
    <td style="white-space: nowrap; text-align: right">2.40 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap; text-align: right">151.42</td>
    <td style="white-space: nowrap; text-align: right">6.60 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.13%</td>
    <td style="white-space: nowrap; text-align: right">6.60 ms</td>
    <td style="white-space: nowrap; text-align: right">7.40 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap; text-align: right">68.46</td>
    <td style="white-space: nowrap; text-align: right">14.61 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.96%</td>
    <td style="white-space: nowrap; text-align: right">14.54 ms</td>
    <td style="white-space: nowrap; text-align: right">16.13 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap;text-align: right">495.10</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap; text-align: right">151.42</td>
    <td style="white-space: nowrap; text-align: right">3.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap; text-align: right">68.46</td>
    <td style="white-space: nowrap; text-align: right">7.23x</td>
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
    <td style="white-space: nowrap">recompute corpus digest</td>
    <td style="white-space: nowrap">4.92 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">construct from decoded vectors</td>
    <td style="white-space: nowrap">13.48 MB</td>
    <td>2.74x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">load and verify directory</td>
    <td style="white-space: nowrap">14.75 MB</td>
    <td>3.0x</td>
  </tr>
</table>