# Matter endpoint discovery on the BEAM side

The stages of `Wotex.Matter.discover_endpoints/3` over a synthetic bridge
with 4, 16 and 32 endpoints (root, aggregator and bridged On/Off Lights).
Discovery reads the four Descriptor attributes of the root endpoint, then
of the remaining endpoints in batches of 16. `Wotex.Matter.Native.Wire.frame/1`
admits each batch's native response line under the shared IPC bounds,
`Wotex.Matter.PathResults.normalize/2` validates and orders each batch,
and `Wotex.Matter.EndpointCatalogue.new/1` validates the endpoint graph.
The last job runs the whole facade operation, including Descriptor value
conversion, against an in-process `Wotex.Matter.Client` that answers from
prepared reports; no controller, process or network is involved.


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



__Input: 16 endpoints__

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
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap; text-align: right">151771.27</td>
    <td style="white-space: nowrap; text-align: right">0.00659 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;41.22%</td>
    <td style="white-space: nowrap; text-align: right">0.00621 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0150 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap; text-align: right">937.03</td>
    <td style="white-space: nowrap; text-align: right">1.07 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.35%</td>
    <td style="white-space: nowrap; text-align: right">1.04 ms</td>
    <td style="white-space: nowrap; text-align: right">1.22 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap; text-align: right">367.27</td>
    <td style="white-space: nowrap; text-align: right">2.72 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.66%</td>
    <td style="white-space: nowrap; text-align: right">2.72 ms</td>
    <td style="white-space: nowrap; text-align: right">2.91 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">343.46</td>
    <td style="white-space: nowrap; text-align: right">2.91 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.63%</td>
    <td style="white-space: nowrap; text-align: right">2.91 ms</td>
    <td style="white-space: nowrap; text-align: right">3.15 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap;text-align: right">151771.27</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap; text-align: right">937.03</td>
    <td style="white-space: nowrap; text-align: right">161.97x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap; text-align: right">367.27</td>
    <td style="white-space: nowrap; text-align: right">413.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">343.46</td>
    <td style="white-space: nowrap; text-align: right">441.89x</td>
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
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap">0.0517 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap">1.66 MB</td>
    <td>32.11x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap">0.88 MB</td>
    <td>17.04x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap">1.67 MB</td>
    <td>32.34x</td>
  </tr>
</table>



__Input: 32 endpoints__

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
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap; text-align: right">66556.44</td>
    <td style="white-space: nowrap; text-align: right">0.0150 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.35%</td>
    <td style="white-space: nowrap; text-align: right">0.0145 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0224 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap; text-align: right">460.47</td>
    <td style="white-space: nowrap; text-align: right">2.17 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.00%</td>
    <td style="white-space: nowrap; text-align: right">2.15 ms</td>
    <td style="white-space: nowrap; text-align: right">2.37 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap; text-align: right">167.12</td>
    <td style="white-space: nowrap; text-align: right">5.98 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.14%</td>
    <td style="white-space: nowrap; text-align: right">5.98 ms</td>
    <td style="white-space: nowrap; text-align: right">6.36 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">155.62</td>
    <td style="white-space: nowrap; text-align: right">6.43 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.87%</td>
    <td style="white-space: nowrap; text-align: right">6.42 ms</td>
    <td style="white-space: nowrap; text-align: right">6.75 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap;text-align: right">66556.44</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap; text-align: right">460.47</td>
    <td style="white-space: nowrap; text-align: right">144.54x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap; text-align: right">167.12</td>
    <td style="white-space: nowrap; text-align: right">398.26x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">155.62</td>
    <td style="white-space: nowrap; text-align: right">427.7x</td>
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
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap">0.117 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap">3.35 MB</td>
    <td>28.69x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap">1.80 MB</td>
    <td>15.39x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap">3.79 MB</td>
    <td>32.42x</td>
  </tr>
</table>



__Input: 4 endpoints__

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
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap; text-align: right">632.83 K</td>
    <td style="white-space: nowrap; text-align: right">1.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;361.30%</td>
    <td style="white-space: nowrap; text-align: right">1.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.29 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap; text-align: right">14.43 K</td>
    <td style="white-space: nowrap; text-align: right">69.31 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.88%</td>
    <td style="white-space: nowrap; text-align: right">68.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">88.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">10.25 K</td>
    <td style="white-space: nowrap; text-align: right">97.51 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.49%</td>
    <td style="white-space: nowrap; text-align: right">95.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">125.70 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap; text-align: right">4.13 K</td>
    <td style="white-space: nowrap; text-align: right">241.95 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.01%</td>
    <td style="white-space: nowrap; text-align: right">239.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">316.92 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap;text-align: right">632.83 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap; text-align: right">14.43 K</td>
    <td style="white-space: nowrap; text-align: right">43.86x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap; text-align: right">10.25 K</td>
    <td style="white-space: nowrap; text-align: right">61.71x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap; text-align: right">4.13 K</td>
    <td style="white-space: nowrap; text-align: right">153.11x</td>
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
    <td style="white-space: nowrap">build endpoint catalogue</td>
    <td style="white-space: nowrap">11.21 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">normalize batch-read results</td>
    <td style="white-space: nowrap">188.45 KB</td>
    <td>16.81x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">discover endpoints through an in-process client</td>
    <td style="white-space: nowrap">342.76 KB</td>
    <td>30.57x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit native response frames</td>
    <td style="white-space: nowrap">403.55 KB</td>
    <td>36.0x</td>
  </tr>
</table>