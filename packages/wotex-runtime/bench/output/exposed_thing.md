# ExposedThing construction and dispatch

`Wotex.Runtime.ExposedThing` over the Thing Descriptions of the
ConsumedThing benchmark, with a `readproperty` handler for every Property,
an `invokeaction` handler and a Thing-level `readallproperties` handler.
Construction includes Thing Description and handler validation. Dispatch
checks the declared operation and Interaction Affordance (or top-level
Form) and calls a handler that returns at once.


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
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap; text-align: right">12.33 M</td>
    <td style="white-space: nowrap; text-align: right">81.09 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1574.60%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap; text-align: right">10.43 M</td>
    <td style="white-space: nowrap; text-align: right">95.87 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5315.86%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap; text-align: right">10.30 M</td>
    <td style="white-space: nowrap; text-align: right">97.08 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1793.63%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap; text-align: right">0.0193 M</td>
    <td style="white-space: nowrap; text-align: right">51927.22 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.63%</td>
    <td style="white-space: nowrap; text-align: right">51000 ns</td>
    <td style="white-space: nowrap; text-align: right">65891.68 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap;text-align: right">12.33 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap; text-align: right">10.43 M</td>
    <td style="white-space: nowrap; text-align: right">1.18x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap; text-align: right">10.30 M</td>
    <td style="white-space: nowrap; text-align: right">1.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap; text-align: right">0.0193 M</td>
    <td style="white-space: nowrap; text-align: right">640.33x</td>
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
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap">128 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap">72 B</td>
    <td>0.56x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap">104 B</td>
    <td>0.81x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap">132704 B</td>
    <td>1036.75x</td>
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
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap; text-align: right">11.76 M</td>
    <td style="white-space: nowrap; text-align: right">85.05 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4877.25%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap; text-align: right">10.84 M</td>
    <td style="white-space: nowrap; text-align: right">92.28 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6316.58%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap; text-align: right">3.15 M</td>
    <td style="white-space: nowrap; text-align: right">317.69 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1681.61%</td>
    <td style="white-space: nowrap; text-align: right">292 ns</td>
    <td style="white-space: nowrap; text-align: right">416 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap; text-align: right">0.00424 M</td>
    <td style="white-space: nowrap; text-align: right">235763.11 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.38%</td>
    <td style="white-space: nowrap; text-align: right">232083 ns</td>
    <td style="white-space: nowrap; text-align: right">288076.85 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap;text-align: right">11.76 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap; text-align: right">10.84 M</td>
    <td style="white-space: nowrap; text-align: right">1.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap; text-align: right">3.15 M</td>
    <td style="white-space: nowrap; text-align: right">3.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap; text-align: right">0.00424 M</td>
    <td style="white-space: nowrap; text-align: right">2771.97x</td>
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
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap">128 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap">72 B</td>
    <td>0.56x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap">104 B</td>
    <td>0.81x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap">596024 B</td>
    <td>4656.44x</td>
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
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap; text-align: right">10.15 M</td>
    <td style="white-space: nowrap; text-align: right">98.55 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3795.56%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap; text-align: right">9.92 M</td>
    <td style="white-space: nowrap; text-align: right">100.79 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5112.32%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap; text-align: right">8.35 M</td>
    <td style="white-space: nowrap; text-align: right">119.79 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1605.07%</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap; text-align: right">0.00055 M</td>
    <td style="white-space: nowrap; text-align: right">1817028.68 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.56%</td>
    <td style="white-space: nowrap; text-align: right">1792833 ns</td>
    <td style="white-space: nowrap; text-align: right">2051943.68 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap;text-align: right">10.15 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap; text-align: right">9.92 M</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap; text-align: right">8.35 M</td>
    <td style="white-space: nowrap; text-align: right">1.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap; text-align: right">0.00055 M</td>
    <td style="white-space: nowrap; text-align: right">18438.56x</td>
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
    <td style="white-space: nowrap">dispatch invokeaction</td>
    <td style="white-space: nowrap">128 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">dispatch_thing readallproperties</td>
    <td style="white-space: nowrap">72 B</td>
    <td>0.56x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">dispatch readproperty</td>
    <td style="white-space: nowrap">104 B</td>
    <td>0.81x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new (validates the Thing Description and handlers)</td>
    <td style="white-space: nowrap">4974904 B</td>
    <td>38866.44x</td>
  </tr>
</table>