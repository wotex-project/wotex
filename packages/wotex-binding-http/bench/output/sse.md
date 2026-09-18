# Server-Sent Event decoding

The per-event work of an open Server-Sent Events stream. A client builds
one `Wotex.Binding.HTTP.SSE.Event` per dispatched event, with an event
type, identifier and retry hint; the Runtime subscription process decodes
it with `Wotex.Binding.HTTP.Transport.decode_frame/3` for an
`observeproperty` stream, which applies the default 1 MiB event limit,
decodes the JSON data and builds the delivery metadata. The event data is
a JSON object with one, 16 or 256 members.


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
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap; text-align: right">1.10 M</td>
    <td style="white-space: nowrap; text-align: right">0.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1251.63%</td>
    <td style="white-space: nowrap; text-align: right">0.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">0.56 M</td>
    <td style="white-space: nowrap; text-align: right">1.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;386.95%</td>
    <td style="white-space: nowrap; text-align: right">1.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.21 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap;text-align: right">1.10 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">0.56 M</td>
    <td style="white-space: nowrap; text-align: right">1.97x</td>
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
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap">0.48 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap">3.60 KB</td>
    <td>7.56x</td>
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
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap; text-align: right">1.07 M</td>
    <td style="white-space: nowrap; text-align: right">0.93 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1239.74%</td>
    <td style="white-space: nowrap; text-align: right">0.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">0.0388 M</td>
    <td style="white-space: nowrap; text-align: right">25.80 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.52%</td>
    <td style="white-space: nowrap; text-align: right">24.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">35.75 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap;text-align: right">1.07 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">0.0388 M</td>
    <td style="white-space: nowrap; text-align: right">27.7x</td>
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
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap">0.48 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap">45.39 KB</td>
    <td>95.25x</td>
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
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap; text-align: right">1.05 M</td>
    <td style="white-space: nowrap; text-align: right">0.95 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1226.21%</td>
    <td style="white-space: nowrap; text-align: right">0.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">0.00220 M</td>
    <td style="white-space: nowrap; text-align: right">453.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.37%</td>
    <td style="white-space: nowrap; text-align: right">446.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">546.50 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap;text-align: right">1.05 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap; text-align: right">0.00220 M</td>
    <td style="white-space: nowrap; text-align: right">477.84x</td>
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
    <td style="white-space: nowrap">Event.new/2</td>
    <td style="white-space: nowrap">0.48 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode_frame/3</td>
    <td style="white-space: nowrap">731.09 KB</td>
    <td>1534.08x</td>
  </tr>
</table>