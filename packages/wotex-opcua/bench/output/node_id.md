# OPC UA NodeId and namespace identity

`Wotex.OPCUA.Address.new/1` and `to_string/1` (standard NodeId text),
`Wotex.OPCUA.Binary.encode_node_id/1` and `decode_node_id/1` (Part 6
binary NodeId in its shortest form) and the ExpandedNodeId codecs with an
explicit namespace URI in place of the namespace index. Inputs are one
numeric (the Server CurrentTime variable), one string and one GUID
identifier.


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



__Input: GUID__

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
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap; text-align: right">36.56 M</td>
    <td style="white-space: nowrap; text-align: right">27.35 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2637.95%</td>
    <td style="white-space: nowrap; text-align: right">25 ns</td>
    <td style="white-space: nowrap; text-align: right">37.50 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap; text-align: right">36.12 M</td>
    <td style="white-space: nowrap; text-align: right">27.69 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2695.48%</td>
    <td style="white-space: nowrap; text-align: right">25 ns</td>
    <td style="white-space: nowrap; text-align: right">37.50 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">7.65 M</td>
    <td style="white-space: nowrap; text-align: right">130.69 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;586.47%</td>
    <td style="white-space: nowrap; text-align: right">120.90 ns</td>
    <td style="white-space: nowrap; text-align: right">175 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap; text-align: right">4.94 M</td>
    <td style="white-space: nowrap; text-align: right">202.61 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2699.92%</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
    <td style="white-space: nowrap; text-align: right">250 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">4.35 M</td>
    <td style="white-space: nowrap; text-align: right">230.10 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;48.66%</td>
    <td style="white-space: nowrap; text-align: right">209 ns</td>
    <td style="white-space: nowrap; text-align: right">333 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap; text-align: right">0.66 M</td>
    <td style="white-space: nowrap; text-align: right">1506.28 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;441.45%</td>
    <td style="white-space: nowrap; text-align: right">1250 ns</td>
    <td style="white-space: nowrap; text-align: right">2417 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap;text-align: right">36.56 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap; text-align: right">36.12 M</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">7.65 M</td>
    <td style="white-space: nowrap; text-align: right">4.78x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap; text-align: right">4.94 M</td>
    <td style="white-space: nowrap; text-align: right">7.41x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">4.35 M</td>
    <td style="white-space: nowrap; text-align: right">8.41x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap; text-align: right">0.66 M</td>
    <td style="white-space: nowrap; text-align: right">55.07x</td>
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
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap">280 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap">208 B</td>
    <td>0.74x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap">608 B</td>
    <td>2.17x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap">456 B</td>
    <td>1.63x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap">1376 B</td>
    <td>4.91x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap">1408 B</td>
    <td>5.03x</td>
  </tr>
</table>



__Input: numeric__

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
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap; text-align: right">59.96 M</td>
    <td style="white-space: nowrap; text-align: right">16.68 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4025.55%</td>
    <td style="white-space: nowrap; text-align: right">12.50 ns</td>
    <td style="white-space: nowrap; text-align: right">25 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap; text-align: right">48.40 M</td>
    <td style="white-space: nowrap; text-align: right">20.66 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4268.60%</td>
    <td style="white-space: nowrap; text-align: right">16.70 ns</td>
    <td style="white-space: nowrap; text-align: right">29.20 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap; text-align: right">16.30 M</td>
    <td style="white-space: nowrap; text-align: right">61.36 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1249.83%</td>
    <td style="white-space: nowrap; text-align: right">58.30 ns</td>
    <td style="white-space: nowrap; text-align: right">75 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">8.47 M</td>
    <td style="white-space: nowrap; text-align: right">118.02 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;752.77%</td>
    <td style="white-space: nowrap; text-align: right">108.40 ns</td>
    <td style="white-space: nowrap; text-align: right">154.20 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">4.55 M</td>
    <td style="white-space: nowrap; text-align: right">219.65 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;45.86%</td>
    <td style="white-space: nowrap; text-align: right">208 ns</td>
    <td style="white-space: nowrap; text-align: right">292 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap; text-align: right">1.47 M</td>
    <td style="white-space: nowrap; text-align: right">680.38 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;872.67%</td>
    <td style="white-space: nowrap; text-align: right">541 ns</td>
    <td style="white-space: nowrap; text-align: right">1125 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap;text-align: right">59.96 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap; text-align: right">48.40 M</td>
    <td style="white-space: nowrap; text-align: right">1.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap; text-align: right">16.30 M</td>
    <td style="white-space: nowrap; text-align: right">3.68x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">8.47 M</td>
    <td style="white-space: nowrap; text-align: right">7.08x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">4.55 M</td>
    <td style="white-space: nowrap; text-align: right">13.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap; text-align: right">1.47 M</td>
    <td style="white-space: nowrap; text-align: right">40.79x</td>
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
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap">128 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap">224 B</td>
    <td>1.75x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap">144 B</td>
    <td>1.13x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap">496 B</td>
    <td>3.88x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap">1288 B</td>
    <td>10.06x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap">768 B</td>
    <td>6.0x</td>
  </tr>
</table>



__Input: string__

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
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap; text-align: right">16.21 M</td>
    <td style="white-space: nowrap; text-align: right">61.70 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1162.07%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap; text-align: right">10.26 M</td>
    <td style="white-space: nowrap; text-align: right">97.43 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4270.91%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap; text-align: right">5.41 M</td>
    <td style="white-space: nowrap; text-align: right">184.73 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;486.26%</td>
    <td style="white-space: nowrap; text-align: right">175 ns</td>
    <td style="white-space: nowrap; text-align: right">245.80 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">3.15 M</td>
    <td style="white-space: nowrap; text-align: right">317.20 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2022.05%</td>
    <td style="white-space: nowrap; text-align: right">250 ns</td>
    <td style="white-space: nowrap; text-align: right">375 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">2.26 M</td>
    <td style="white-space: nowrap; text-align: right">442.03 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;41.53%</td>
    <td style="white-space: nowrap; text-align: right">417 ns</td>
    <td style="white-space: nowrap; text-align: right">625 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap; text-align: right">1.43 M</td>
    <td style="white-space: nowrap; text-align: right">697.21 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1068.42%</td>
    <td style="white-space: nowrap; text-align: right">542 ns</td>
    <td style="white-space: nowrap; text-align: right">917 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap;text-align: right">16.21 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap; text-align: right">10.26 M</td>
    <td style="white-space: nowrap; text-align: right">1.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap; text-align: right">5.41 M</td>
    <td style="white-space: nowrap; text-align: right">2.99x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">3.15 M</td>
    <td style="white-space: nowrap; text-align: right">5.14x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap; text-align: right">2.26 M</td>
    <td style="white-space: nowrap; text-align: right">7.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap; text-align: right">1.43 M</td>
    <td style="white-space: nowrap; text-align: right">11.3x</td>
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
    <td style="white-space: nowrap">format NodeId text</td>
    <td style="white-space: nowrap">176 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode NodeId</td>
    <td style="white-space: nowrap">200 B</td>
    <td>1.14x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode NodeId</td>
    <td style="white-space: nowrap">1016 B</td>
    <td>5.77x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap">656 B</td>
    <td>3.73x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode ExpandedNodeId with namespace URI</td>
    <td style="white-space: nowrap">2416 B</td>
    <td>13.73x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">parse NodeId text</td>
    <td style="white-space: nowrap">728 B</td>
    <td>4.14x</td>
  </tr>
</table>