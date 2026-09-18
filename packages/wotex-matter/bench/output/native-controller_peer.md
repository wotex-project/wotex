# Matter controller against the all-clusters peer

The public `Wotex.Matter` API end to end against the pinned connectedhomeip all-clusters example, commissioned on the network by a persistent controller: the BEAM client, the Port, the first-party controller host and the SDK controller, and the peer. The jobs read OnOff, read the four Descriptor attributes of two endpoints in one batch, discover the endpoints, write the Thermostat OccupiedHeatingSetpoint, invoke the OnOff Toggle command, and invoke Toggle and wait for the resulting OnOff subscription report. The controller host and the peer are the x86_64 Linux builds of `mix wotex.software.build`, so the benchmark runs in the software lane's linux/amd64 hexpm/elixir container on a private Docker network; on an arm64 host that container's user space is translated (Rosetta under OrbStack), which slows the BEAM, the host and the peer alike. The controller host writes the SDK's log to its standard error, here a file, as it does in production; that cost is part of every measurement.

## System

Benchmark suite executing on the following system:

<table style="width: 1%">
  <tr>
    <th style="width: 1%; white-space: nowrap">Operating System</th>
    <td>Linux</td>
  </tr><tr>
    <th style="white-space: nowrap">CPU Information</th>
    <td style="white-space: nowrap">VirtualApple @ 2.50GHz</td>
  </tr><tr>
    <th style="white-space: nowrap">Number of Available Cores</th>
    <td style="white-space: nowrap">18</td>
  </tr><tr>
    <th style="white-space: nowrap">Available Memory</th>
    <td style="white-space: nowrap">15.66 GB</td>
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
    <td style="white-space: nowrap">10 s</td>
  </tr><tr>
    <th>:parallel</th>
    <td style="white-space: nowrap">1</td>
  </tr><tr>
    <th>:warmup</th>
    <td style="white-space: nowrap">2 s</td>
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
    <td style="white-space: nowrap">write_attribute OccupiedHeatingSetpoint</td>
    <td style="white-space: nowrap; text-align: right">684.50</td>
    <td style="white-space: nowrap; text-align: right">1.46 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.27%</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
    <td style="white-space: nowrap; text-align: right">1.88 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_attribute OnOff</td>
    <td style="white-space: nowrap; text-align: right">562.05</td>
    <td style="white-space: nowrap; text-align: right">1.78 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.22%</td>
    <td style="white-space: nowrap; text-align: right">1.81 ms</td>
    <td style="white-space: nowrap; text-align: right">2.31 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invoke_command OnOff Toggle</td>
    <td style="white-space: nowrap; text-align: right">246.99</td>
    <td style="white-space: nowrap; text-align: right">4.05 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;46.04%</td>
    <td style="white-space: nowrap; text-align: right">3.93 ms</td>
    <td style="white-space: nowrap; text-align: right">7.15 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Toggle until its OnOff subscription report</td>
    <td style="white-space: nowrap; text-align: right">184.33</td>
    <td style="white-space: nowrap; text-align: right">5.43 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.50%</td>
    <td style="white-space: nowrap; text-align: right">5.35 ms</td>
    <td style="white-space: nowrap; text-align: right">7.21 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_paths Descriptor of two endpoints (8 paths)</td>
    <td style="white-space: nowrap; text-align: right">140.38</td>
    <td style="white-space: nowrap; text-align: right">7.12 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.43%</td>
    <td style="white-space: nowrap; text-align: right">7.02 ms</td>
    <td style="white-space: nowrap; text-align: right">8.16 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">discover_endpoints</td>
    <td style="white-space: nowrap; text-align: right">70.54</td>
    <td style="white-space: nowrap; text-align: right">14.18 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.97%</td>
    <td style="white-space: nowrap; text-align: right">14.14 ms</td>
    <td style="white-space: nowrap; text-align: right">15.62 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">write_attribute OccupiedHeatingSetpoint</td>
    <td style="white-space: nowrap;text-align: right">684.50</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_attribute OnOff</td>
    <td style="white-space: nowrap; text-align: right">562.05</td>
    <td style="white-space: nowrap; text-align: right">1.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invoke_command OnOff Toggle</td>
    <td style="white-space: nowrap; text-align: right">246.99</td>
    <td style="white-space: nowrap; text-align: right">2.77x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Toggle until its OnOff subscription report</td>
    <td style="white-space: nowrap; text-align: right">184.33</td>
    <td style="white-space: nowrap; text-align: right">3.71x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">read_paths Descriptor of two endpoints (8 paths)</td>
    <td style="white-space: nowrap; text-align: right">140.38</td>
    <td style="white-space: nowrap; text-align: right">4.88x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">discover_endpoints</td>
    <td style="white-space: nowrap; text-align: right">70.54</td>
    <td style="white-space: nowrap; text-align: right">9.7x</td>
  </tr>

</table>