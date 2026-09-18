# Knowledge graph generation and representations

`Wotex.Lab.Graph` over its real subject: this Lab checkout with the
documentation tree `Wotex.Lab.Documentation` locates, the specification
catalogue decoded before the run, a fixed source revision and a fixed
generation time. For this run the graph has 238 nodes and 522
edges. The subject changes with the repository, so results from
different commits are not directly comparable.

`generate` is `Wotex.Lab.Graph.generate/1`: reading the source index and
source cohort (decoded with `Wotex.JSON.decode/2`), the completion plan,
the fixture manifests with a check of each fixture's input and expected
output digests, the README, the cookbook notebooks and every
documentation page; digesting the package source tree (`lib`, `priv`,
`mix.exs`, `README.md`, `CHANGELOG.md`); and joining them with the
cookbook catalogue and the scenario, adapter and seam descriptors into
one validated graph. `render ecosystem.ttl (Turtle)`,
`render asyncapi.yaml` and `render llms.txt` are
`Wotex.Lab.Graph.render/2` for the representations the Lab serializes
itself: RDF 1.1 Turtle, the AsyncAPI document through the block YAML
emitter, and `llms.txt`. Turtle and YAML quote string literals with
`Wotex.JSON.encode/1`. The representations that are a projection passed
whole to `Wotex.JSON.encode/1` are left out.
`answer every ownership question` is `Wotex.Lab.Graph.answer/2` for each
of the 8 ownership questions. Every job compares its
result with the value computed before the run.


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



__Input: wotex-lab checkout__

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
    <td style="white-space: nowrap">render llms.txt</td>
    <td style="white-space: nowrap; text-align: right">70.06 K</td>
    <td style="white-space: nowrap; text-align: right">14.27 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;32.62%</td>
    <td style="white-space: nowrap; text-align: right">13.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">26.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">answer every ownership question</td>
    <td style="white-space: nowrap; text-align: right">11.65 K</td>
    <td style="white-space: nowrap; text-align: right">85.86 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.09%</td>
    <td style="white-space: nowrap; text-align: right">84.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">104.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render asyncapi.yaml</td>
    <td style="white-space: nowrap; text-align: right">7.50 K</td>
    <td style="white-space: nowrap; text-align: right">133.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;53.23%</td>
    <td style="white-space: nowrap; text-align: right">85.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">268.14 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render ecosystem.ttl (Turtle)</td>
    <td style="white-space: nowrap; text-align: right">0.21 K</td>
    <td style="white-space: nowrap; text-align: right">4801.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.42%</td>
    <td style="white-space: nowrap; text-align: right">4654.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5548.47 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">generate</td>
    <td style="white-space: nowrap; text-align: right">0.0447 K</td>
    <td style="white-space: nowrap; text-align: right">22349.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.03%</td>
    <td style="white-space: nowrap; text-align: right">21820.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">27587.74 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">render llms.txt</td>
    <td style="white-space: nowrap;text-align: right">70.06 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">answer every ownership question</td>
    <td style="white-space: nowrap; text-align: right">11.65 K</td>
    <td style="white-space: nowrap; text-align: right">6.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render asyncapi.yaml</td>
    <td style="white-space: nowrap; text-align: right">7.50 K</td>
    <td style="white-space: nowrap; text-align: right">9.34x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render ecosystem.ttl (Turtle)</td>
    <td style="white-space: nowrap; text-align: right">0.21 K</td>
    <td style="white-space: nowrap; text-align: right">336.41x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">generate</td>
    <td style="white-space: nowrap; text-align: right">0.0447 K</td>
    <td style="white-space: nowrap; text-align: right">1565.77x</td>
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
    <td style="white-space: nowrap">render llms.txt</td>
    <td style="white-space: nowrap">6.73 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">answer every ownership question</td>
    <td style="white-space: nowrap">6.54 KB</td>
    <td>0.97x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">render asyncapi.yaml</td>
    <td style="white-space: nowrap">204.73 KB</td>
    <td>30.4x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">render ecosystem.ttl (Turtle)</td>
    <td style="white-space: nowrap">5371.47 KB</td>
    <td>797.62x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">generate</td>
    <td style="white-space: nowrap">10695.81 KB</td>
    <td>1588.24x</td>
  </tr>
</table>