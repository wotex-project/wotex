# Form mapping and finite request round trips

The `c:Wotex.Runtime.Transport.request/3` callback of
`Wotex.Binding.HTTP.Transport` for Runtime requests selected from a
synthetic Thing Description, against an in-memory client that returns a
prepared `Wotex.Binding.HTTP.Response`. Each round trip maps the Form to a
`Wotex.Binding.HTTP.Request`, calls the client, revalidates the response
fields and builds the Runtime result. The Property value and Action input
is a JSON object with one, 16 or 256 members; `readproperty` decodes it
from a 200 response, `writeproperty` encodes it and receives 204, and
`invokeaction` encodes it, uses an explicit `htv:methodName` and
`htv:headers`, and resolves the `Location` of a 201 response.
`Wotex.Binding.HTTP.Codec` alone is the bounded JSON baseline.


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
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap; text-align: right">574.40 K</td>
    <td style="white-space: nowrap; text-align: right">1.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;397.42%</td>
    <td style="white-space: nowrap; text-align: right">1.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap; text-align: right">504.64 K</td>
    <td style="white-space: nowrap; text-align: right">1.98 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;306.85%</td>
    <td style="white-space: nowrap; text-align: right">1.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap; text-align: right">113.25 K</td>
    <td style="white-space: nowrap; text-align: right">8.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;113.33%</td>
    <td style="white-space: nowrap; text-align: right">7.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">30.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap; text-align: right">112.10 K</td>
    <td style="white-space: nowrap; text-align: right">8.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;107.44%</td>
    <td style="white-space: nowrap; text-align: right">7.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">30.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap; text-align: right">49.84 K</td>
    <td style="white-space: nowrap; text-align: right">20.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;24.77%</td>
    <td style="white-space: nowrap; text-align: right">18.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">40.04 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap;text-align: right">574.40 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap; text-align: right">504.64 K</td>
    <td style="white-space: nowrap; text-align: right">1.14x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap; text-align: right">113.25 K</td>
    <td style="white-space: nowrap; text-align: right">5.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap; text-align: right">112.10 K</td>
    <td style="white-space: nowrap; text-align: right">5.12x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap; text-align: right">49.84 K</td>
    <td style="white-space: nowrap; text-align: right">11.53x</td>
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
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap">3.51 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap">4.64 KB</td>
    <td>1.32x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap">13.59 KB</td>
    <td>3.87x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap">14.64 KB</td>
    <td>4.17x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap">29.23 KB</td>
    <td>8.33x</td>
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
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap; text-align: right">34.74 K</td>
    <td style="white-space: nowrap; text-align: right">28.78 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.67%</td>
    <td style="white-space: nowrap; text-align: right">27.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">39.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap; text-align: right">34.35 K</td>
    <td style="white-space: nowrap; text-align: right">29.11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.50%</td>
    <td style="white-space: nowrap; text-align: right">28.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">37.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap; text-align: right">26.99 K</td>
    <td style="white-space: nowrap; text-align: right">37.05 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.00%</td>
    <td style="white-space: nowrap; text-align: right">35.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">52.29 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap; text-align: right">25.73 K</td>
    <td style="white-space: nowrap; text-align: right">38.87 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.39%</td>
    <td style="white-space: nowrap; text-align: right">37.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">54.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap; text-align: right">19.34 K</td>
    <td style="white-space: nowrap; text-align: right">51.70 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.86%</td>
    <td style="white-space: nowrap; text-align: right">49.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">70.71 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap;text-align: right">34.74 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap; text-align: right">34.35 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap; text-align: right">26.99 K</td>
    <td style="white-space: nowrap; text-align: right">1.29x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap; text-align: right">25.73 K</td>
    <td style="white-space: nowrap; text-align: right">1.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap; text-align: right">19.34 K</td>
    <td style="white-space: nowrap; text-align: right">1.8x</td>
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
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap">45.36 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap">66.82 KB</td>
    <td>1.47x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap">76.70 KB</td>
    <td>1.69x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap">55.44 KB</td>
    <td>1.22x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap">91.29 KB</td>
    <td>2.01x</td>
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
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap; text-align: right">1.93 K</td>
    <td style="white-space: nowrap; text-align: right">517.03 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.68%</td>
    <td style="white-space: nowrap; text-align: right">504.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">656.16 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap; text-align: right">1.92 K</td>
    <td style="white-space: nowrap; text-align: right">520.40 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.16%</td>
    <td style="white-space: nowrap; text-align: right">507.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">646.10 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap; text-align: right">1.89 K</td>
    <td style="white-space: nowrap; text-align: right">529.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.59%</td>
    <td style="white-space: nowrap; text-align: right">525.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">629.69 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap; text-align: right">1.86 K</td>
    <td style="white-space: nowrap; text-align: right">537.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.78%</td>
    <td style="white-space: nowrap; text-align: right">527.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">676.31 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">584.84 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.95%</td>
    <td style="white-space: nowrap; text-align: right">572.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">711.08 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap;text-align: right">1.93 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap; text-align: right">1.92 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap; text-align: right">1.89 K</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap; text-align: right">1.86 K</td>
    <td style="white-space: nowrap; text-align: right">1.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">1.13x</td>
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
    <td style="white-space: nowrap">readproperty: GET and decode</td>
    <td style="white-space: nowrap">0.72 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode/2</td>
    <td style="white-space: nowrap">1.05 MB</td>
    <td>1.45x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.decode/2</td>
    <td style="white-space: nowrap">0.71 MB</td>
    <td>0.99x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty: encode and PUT</td>
    <td style="white-space: nowrap">1.06 MB</td>
    <td>1.47x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">invokeaction: encode, POST and resolve Location</td>
    <td style="white-space: nowrap">1.07 MB</td>
    <td>1.48x</td>
  </tr>
</table>