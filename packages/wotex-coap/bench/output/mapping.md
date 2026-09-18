# Form mapping and representation conversion

`Wotex.CoAP.Mapping.command/4` over three Forms of the draft CoAP profile:
a JSON `readproperty` GET with an unknown extension term, a confirmable
`writeproperty` PUT of a 16-member JSON object with a Uri-Query, and an
`invokeaction` POST of a 48-member object. Mapping validates the Form and
operation, the `coap` endpoint and the content format, encodes the input as
JSON and builds the request options. The request is then encoded with
`Wotex.CoAP.Codec.encode/1`, and the reply (2.05 with the number, 2.04
without a payload, 2.05 with a 48-member object) is decoded with
`Wotex.CoAP.Codec.decode/1` and converted with
`Wotex.CoAP.Mapping.decode/2`.


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



__Input: invokeaction, 48-member object__

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
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap; text-align: right">2254.23 K</td>
    <td style="white-space: nowrap; text-align: right">0.44 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1242.28%</td>
    <td style="white-space: nowrap; text-align: right">0.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap; text-align: right">37.04 K</td>
    <td style="white-space: nowrap; text-align: right">27.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.55%</td>
    <td style="white-space: nowrap; text-align: right">26.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">35.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap; text-align: right">28.45 K</td>
    <td style="white-space: nowrap; text-align: right">35.14 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.36%</td>
    <td style="white-space: nowrap; text-align: right">34.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">46.13 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap;text-align: right">2254.23 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap; text-align: right">37.04 K</td>
    <td style="white-space: nowrap; text-align: right">60.86x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap; text-align: right">28.45 K</td>
    <td style="white-space: nowrap; text-align: right">79.22x</td>
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
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap">1.41 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap">40.72 KB</td>
    <td>28.96x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap">76.53 KB</td>
    <td>54.42x</td>
  </tr>
</table>



__Input: readproperty, number__

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
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap; text-align: right">4.68 M</td>
    <td style="white-space: nowrap; text-align: right">213.90 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2605.36%</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
    <td style="white-space: nowrap; text-align: right">292 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap; text-align: right">2.05 M</td>
    <td style="white-space: nowrap; text-align: right">487.29 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;700.42%</td>
    <td style="white-space: nowrap; text-align: right">458 ns</td>
    <td style="white-space: nowrap; text-align: right">625 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap; text-align: right">0.0579 M</td>
    <td style="white-space: nowrap; text-align: right">17265.34 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.18%</td>
    <td style="white-space: nowrap; text-align: right">16542 ns</td>
    <td style="white-space: nowrap; text-align: right">28709 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap;text-align: right">4.68 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap; text-align: right">2.05 M</td>
    <td style="white-space: nowrap; text-align: right">2.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap; text-align: right">0.0579 M</td>
    <td style="white-space: nowrap; text-align: right">80.72x</td>
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
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap">0.91 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap">1.79 KB</td>
    <td>1.96x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap">30.22 KB</td>
    <td>33.06x</td>
  </tr>
</table>



__Input: writeproperty, 16-member object__

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
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap; text-align: right">5.49 M</td>
    <td style="white-space: nowrap; text-align: right">182.21 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2236.73%</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
    <td style="white-space: nowrap; text-align: right">291 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap; text-align: right">2.00 M</td>
    <td style="white-space: nowrap; text-align: right">499.36 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1138.36%</td>
    <td style="white-space: nowrap; text-align: right">334 ns</td>
    <td style="white-space: nowrap; text-align: right">1000 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap; text-align: right">0.0431 M</td>
    <td style="white-space: nowrap; text-align: right">23181.71 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.35%</td>
    <td style="white-space: nowrap; text-align: right">22333 ns</td>
    <td style="white-space: nowrap; text-align: right">31750 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap;text-align: right">5.49 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap; text-align: right">2.00 M</td>
    <td style="white-space: nowrap; text-align: right">2.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap; text-align: right">0.0431 M</td>
    <td style="white-space: nowrap; text-align: right">127.22x</td>
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
    <td style="white-space: nowrap">decode response and value</td>
    <td style="white-space: nowrap">0.88 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode request datagram</td>
    <td style="white-space: nowrap">1.70 KB</td>
    <td>1.94x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map Form to request</td>
    <td style="white-space: nowrap">45.78 KB</td>
    <td>52.32x</td>
  </tr>
</table>