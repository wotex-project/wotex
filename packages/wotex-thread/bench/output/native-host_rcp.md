# Thread host against the simulated RCP

The public `Wotex.Thread` API end to end: the BEAM client, the Port, the first-party OpenThread host of the native build and the pinned OpenThread simulation RCP over Spinel, on a network the host formed as leader with its commissioner active. The jobs inspect the State, export and validate the Active Dataset, open a State subscription, receive its initial report and close it, send a `MGMT_ACTIVE_SET` with a newer Active Timestamp to the leader, and add and remove one joiner admission.

## System

Benchmark suite executing on the following system:

<table style="width: 1%">
  <tr>
    <th style="width: 1%; white-space: nowrap">Operating System</th>
    <td>Linux</td>
  </tr><tr>
    <th style="white-space: nowrap">CPU Information</th>
    <td style="white-space: nowrap">Unrecognized processor</td>
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
    <td style="white-space: nowrap">inspect_state</td>
    <td style="white-space: nowrap; text-align: right">16.80 K</td>
    <td style="white-space: nowrap; text-align: right">59.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;24.76%</td>
    <td style="white-space: nowrap; text-align: right">57.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">81.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">get_dataset active</td>
    <td style="white-space: nowrap; text-align: right">14.02 K</td>
    <td style="white-space: nowrap; text-align: right">71.35 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.23%</td>
    <td style="white-space: nowrap; text-align: right">74.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">89.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate_dataset active</td>
    <td style="white-space: nowrap; text-align: right">13.78 K</td>
    <td style="white-space: nowrap; text-align: right">72.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;41.91%</td>
    <td style="white-space: nowrap; text-align: right">76.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">98.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">add_joiner and remove_joiner</td>
    <td style="white-space: nowrap; text-align: right">6.18 K</td>
    <td style="white-space: nowrap; text-align: right">161.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;35.89%</td>
    <td style="white-space: nowrap; text-align: right">170.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">203.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">subscribe State, initial report, unsubscribe</td>
    <td style="white-space: nowrap; text-align: right">6.16 K</td>
    <td style="white-space: nowrap; text-align: right">162.39 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.62%</td>
    <td style="white-space: nowrap; text-align: right">170.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">193.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">management_active_set newer timestamp</td>
    <td style="white-space: nowrap; text-align: right">0.52 K</td>
    <td style="white-space: nowrap; text-align: right">1916.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;36.75%</td>
    <td style="white-space: nowrap; text-align: right">1645.60 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4058.80 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">inspect_state</td>
    <td style="white-space: nowrap;text-align: right">16.80 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">get_dataset active</td>
    <td style="white-space: nowrap; text-align: right">14.02 K</td>
    <td style="white-space: nowrap; text-align: right">1.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate_dataset active</td>
    <td style="white-space: nowrap; text-align: right">13.78 K</td>
    <td style="white-space: nowrap; text-align: right">1.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">add_joiner and remove_joiner</td>
    <td style="white-space: nowrap; text-align: right">6.18 K</td>
    <td style="white-space: nowrap; text-align: right">2.72x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">subscribe State, initial report, unsubscribe</td>
    <td style="white-space: nowrap; text-align: right">6.16 K</td>
    <td style="white-space: nowrap; text-align: right">2.73x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">management_active_set newer timestamp</td>
    <td style="white-space: nowrap; text-align: right">0.52 K</td>
    <td style="white-space: nowrap; text-align: right">32.18x</td>
  </tr>

</table>