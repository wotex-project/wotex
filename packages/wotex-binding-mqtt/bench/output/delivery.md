# Delivery decoding in the subscription owner

The per-message work of an `observeproperty` subscription. A client builds
one `Wotex.Binding.MQTT.Delivery` per received Application Message, which
validates its Topic Name and QoS; the Runtime subscription process decodes
it with the `c:Wotex.Runtime.Transport.decode_frame/3` callback of
`Wotex.Binding.MQTT.Transport`, which maps the Form to its SUBSCRIBE
command again, matches the Topic Name against the
`things/+/properties/state` filter, decodes the JSON payload under the
default 1 MiB limit and builds the delivery metadata.
`Wotex.Binding.MQTT.JSON.decode/2` alone is the decoding baseline. The
payload is a JSON object with one, 16 or 256 members.


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
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap; text-align: right">1485.81 K</td>
    <td style="white-space: nowrap; text-align: right">0.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;674.94%</td>
    <td style="white-space: nowrap; text-align: right">0.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap; text-align: right">550.46 K</td>
    <td style="white-space: nowrap; text-align: right">1.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;384.30%</td>
    <td style="white-space: nowrap; text-align: right">1.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">95.37 K</td>
    <td style="white-space: nowrap; text-align: right">10.49 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.83%</td>
    <td style="white-space: nowrap; text-align: right">9.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">21.58 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap;text-align: right">1485.81 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap; text-align: right">550.46 K</td>
    <td style="white-space: nowrap; text-align: right">2.7x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">95.37 K</td>
    <td style="white-space: nowrap; text-align: right">15.58x</td>
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
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap">0.22 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap">3.51 KB</td>
    <td>16.04x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap">9.52 KB</td>
    <td>43.5x</td>
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
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap; text-align: right">1534.83 K</td>
    <td style="white-space: nowrap; text-align: right">0.65 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;629.28%</td>
    <td style="white-space: nowrap; text-align: right">0.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap; text-align: right">31.60 K</td>
    <td style="white-space: nowrap; text-align: right">31.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.06%</td>
    <td style="white-space: nowrap; text-align: right">31.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">43.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">24.24 K</td>
    <td style="white-space: nowrap; text-align: right">41.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.71%</td>
    <td style="white-space: nowrap; text-align: right">40.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">55.33 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap;text-align: right">1534.83 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap; text-align: right">31.60 K</td>
    <td style="white-space: nowrap; text-align: right">48.57x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">24.24 K</td>
    <td style="white-space: nowrap; text-align: right">63.32x</td>
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
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap">0.22 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap">45.36 KB</td>
    <td>207.36x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap">51.37 KB</td>
    <td>234.82x</td>
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
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap; text-align: right">1534.80 K</td>
    <td style="white-space: nowrap; text-align: right">0.65 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;636.57%</td>
    <td style="white-space: nowrap; text-align: right">0.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">531.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.51%</td>
    <td style="white-space: nowrap; text-align: right">524.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">617.38 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">1.84 K</td>
    <td style="white-space: nowrap; text-align: right">542.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.20%</td>
    <td style="white-space: nowrap; text-align: right">537.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">620.74 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap;text-align: right">1534.80 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">815.62x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">1.84 K</td>
    <td style="white-space: nowrap; text-align: right">832.95x</td>
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
    <td style="white-space: nowrap">Delivery.new/2</td>
    <td style="white-space: nowrap">0.22 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">JSON.decode/2</td>
    <td style="white-space: nowrap">731.05 KB</td>
    <td>3341.96x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap">737.06 KB</td>
    <td>3369.43x</td>
  </tr>
</table>