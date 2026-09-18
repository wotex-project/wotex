# Form mapping and Runtime transport requests

The `c:Wotex.Runtime.Transport.request/3` callback of
`Wotex.Binding.MQTT.Transport` for Runtime requests selected from a
synthetic Thing Description, against an in-memory client port. A
`writeproperty` request maps its Form to a PUBLISH
`Wotex.Binding.MQTT.Command`, encodes the value and returns the
`:accepted` result the client acknowledgement produces; a `readproperty`
request maps a retained SUBSCRIBE command, checks the retained delivery
against its Topic Filter and decodes it. The value is a JSON object with
one, 16 or 256 members. `Wotex.Binding.MQTT.Mapping.command/2` and
`Wotex.Binding.MQTT.JSON.encode/2` alone show the mapping and encoding
shares of a publish.


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



__Input: 1 member__

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
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap; text-align: right">492.31 K</td>
    <td style="white-space: nowrap; text-align: right">2.03 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;319.85%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap; text-align: right">156.20 K</td>
    <td style="white-space: nowrap; text-align: right">6.40 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;88.41%</td>
    <td style="white-space: nowrap; text-align: right">5.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">15.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap; text-align: right">152.79 K</td>
    <td style="white-space: nowrap; text-align: right">6.55 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;93.54%</td>
    <td style="white-space: nowrap; text-align: right">5.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">15.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap; text-align: right">92.98 K</td>
    <td style="white-space: nowrap; text-align: right">10.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;33.30%</td>
    <td style="white-space: nowrap; text-align: right">10.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">20.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap;text-align: right">492.31 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap; text-align: right">156.20 K</td>
    <td style="white-space: nowrap; text-align: right">3.15x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap; text-align: right">152.79 K</td>
    <td style="white-space: nowrap; text-align: right">3.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap; text-align: right">92.98 K</td>
    <td style="white-space: nowrap; text-align: right">5.29x</td>
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
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap">4.78 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap">8.54 KB</td>
    <td>1.79x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap">8.78 KB</td>
    <td>1.84x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap">10.13 KB</td>
    <td>2.12x</td>
  </tr>
</table>



__Input: 16 members__

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
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap; text-align: right">31.50 K</td>
    <td style="white-space: nowrap; text-align: right">31.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.15%</td>
    <td style="white-space: nowrap; text-align: right">31.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">39.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap; text-align: right">29.21 K</td>
    <td style="white-space: nowrap; text-align: right">34.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.57%</td>
    <td style="white-space: nowrap; text-align: right">33.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">45 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap; text-align: right">28.22 K</td>
    <td style="white-space: nowrap; text-align: right">35.44 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.50%</td>
    <td style="white-space: nowrap; text-align: right">33.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">48.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap; text-align: right">24.61 K</td>
    <td style="white-space: nowrap; text-align: right">40.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.87%</td>
    <td style="white-space: nowrap; text-align: right">39.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">55.13 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap;text-align: right">31.50 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap; text-align: right">29.21 K</td>
    <td style="white-space: nowrap; text-align: right">1.08x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap; text-align: right">28.22 K</td>
    <td style="white-space: nowrap; text-align: right">1.12x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap; text-align: right">24.61 K</td>
    <td style="white-space: nowrap; text-align: right">1.28x</td>
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
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap">66.84 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap">70.87 KB</td>
    <td>1.06x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap">70.47 KB</td>
    <td>1.05x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap">52.19 KB</td>
    <td>0.78x</td>
  </tr>
</table>



__Input: 256 members__

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
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap; text-align: right">1.87 K</td>
    <td style="white-space: nowrap; text-align: right">534.11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.23%</td>
    <td style="white-space: nowrap; text-align: right">528 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">629.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap; text-align: right">1.86 K</td>
    <td style="white-space: nowrap; text-align: right">537.81 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.86%</td>
    <td style="white-space: nowrap; text-align: right">530.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">624.07 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap; text-align: right">1.79 K</td>
    <td style="white-space: nowrap; text-align: right">558.20 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.02%</td>
    <td style="white-space: nowrap; text-align: right">550.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">653.27 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">585.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.99%</td>
    <td style="white-space: nowrap; text-align: right">586.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">686.38 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap;text-align: right">1.87 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap; text-align: right">1.86 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap; text-align: right">1.79 K</td>
    <td style="white-space: nowrap; text-align: right">1.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">1.1x</td>
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
    <td style="white-space: nowrap">readproperty: retained read and decode</td>
    <td style="white-space: nowrap">0.72 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty: map, encode and publish</td>
    <td style="white-space: nowrap">1.06 MB</td>
    <td>1.46x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Mapping.command/2 for writeproperty</td>
    <td style="white-space: nowrap">1.05 MB</td>
    <td>1.46x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">JSON.encode/2</td>
    <td style="white-space: nowrap">1.05 MB</td>
    <td>1.46x</td>
  </tr>
</table>