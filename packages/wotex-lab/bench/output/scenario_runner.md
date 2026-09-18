# Scenario admission and runner attempts

The scenario runner's own in-process bookkeeping over chained definitions
of 4 steps (the length of an admitted cookbook scenario), 16 steps and
100 steps (the default step budget). Each step depends on the step before
it and has one assertion on its value, and the definition pins one
packaged fixture by digest. The trusted component echoes its input and
starts no child, so no transport, network or external process is
involved.

`admit descriptor and definition` is `Wotex.Lab.Scenario.new/1` and
`Wotex.Lab.Runner.Definition.new/1` from keyword data: field and bound
checks, unique step ids, known dependencies and the acyclicity check.
`preflight` is `Wotex.Lab.Runner.preflight/3`: the descriptor, definition
and host are rebuilt and compared with their constructed form, the
descriptor and definition must agree, the host must serve every
capability and the pinned fixture is read and digested.
`start and await one attempt` is `Wotex.Lab.Runner.start/3` followed by
`Wotex.Lab.Runner.await/2` until the attempt is terminal with outcome
`pass`: preflight, placing the attempt under the instance's session
supervisor, creating and removing its private work directory, one
monitored worker per step in dependency order, the input and value
digests of the replay recording, the assertions and cleanup. The
terminal attempt is released with `Wotex.Lab.stop_child/3` outside the
measurement; memory is that of the calling process only.


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



__Input: 100 steps__

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
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap; text-align: right">813.40</td>
    <td style="white-space: nowrap; text-align: right">1.23 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.97%</td>
    <td style="white-space: nowrap; text-align: right">1.23 ms</td>
    <td style="white-space: nowrap; text-align: right">1.31 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap; text-align: right">749.27</td>
    <td style="white-space: nowrap; text-align: right">1.33 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.56%</td>
    <td style="white-space: nowrap; text-align: right">1.33 ms</td>
    <td style="white-space: nowrap; text-align: right">1.42 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap; text-align: right">460.72</td>
    <td style="white-space: nowrap; text-align: right">2.17 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.62%</td>
    <td style="white-space: nowrap; text-align: right">2.14 ms</td>
    <td style="white-space: nowrap; text-align: right">2.53 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap;text-align: right">813.40</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap; text-align: right">749.27</td>
    <td style="white-space: nowrap; text-align: right">1.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap; text-align: right">460.72</td>
    <td style="white-space: nowrap; text-align: right">1.77x</td>
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
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap">420.43 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap">447.40 KB</td>
    <td>1.06x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap">482.20 KB</td>
    <td>1.15x</td>
  </tr>
</table>



__Input: 16 steps__

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
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap; text-align: right">16.51 K</td>
    <td style="white-space: nowrap; text-align: right">60.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.29%</td>
    <td style="white-space: nowrap; text-align: right">59 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">86.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap; text-align: right">7.15 K</td>
    <td style="white-space: nowrap; text-align: right">139.87 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.76%</td>
    <td style="white-space: nowrap; text-align: right">138.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">169.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap; text-align: right">1.85 K</td>
    <td style="white-space: nowrap; text-align: right">539.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.88%</td>
    <td style="white-space: nowrap; text-align: right">534.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">714.63 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap;text-align: right">16.51 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap; text-align: right">7.15 K</td>
    <td style="white-space: nowrap; text-align: right">2.31x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap; text-align: right">1.85 K</td>
    <td style="white-space: nowrap; text-align: right">8.9x</td>
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
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap">37.49 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap">56.08 KB</td>
    <td>1.5x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap">58.34 KB</td>
    <td>1.56x</td>
  </tr>
</table>



__Input: 4 steps__

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
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap; text-align: right">70.87 K</td>
    <td style="white-space: nowrap; text-align: right">14.11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;57.93%</td>
    <td style="white-space: nowrap; text-align: right">11.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">73.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap; text-align: right">12.41 K</td>
    <td style="white-space: nowrap; text-align: right">80.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.09%</td>
    <td style="white-space: nowrap; text-align: right">78.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">107.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap; text-align: right">2.24 K</td>
    <td style="white-space: nowrap; text-align: right">446.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.18%</td>
    <td style="white-space: nowrap; text-align: right">439.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">622.71 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap;text-align: right">70.87 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap; text-align: right">12.41 K</td>
    <td style="white-space: nowrap; text-align: right">5.71x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap; text-align: right">2.24 K</td>
    <td style="white-space: nowrap; text-align: right">31.67x</td>
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
    <td style="white-space: nowrap">admit descriptor and definition</td>
    <td style="white-space: nowrap">12.11 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">preflight</td>
    <td style="white-space: nowrap">30.55 KB</td>
    <td>2.52x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">start and await one attempt</td>
    <td style="white-space: nowrap">33.69 KB</td>
    <td>2.78x</td>
  </tr>
</table>