# CoAP message encoding and decoding

`Wotex.CoAP.Codec.encode/1`, `Wotex.CoAP.Codec.decode/1` and
`Wotex.CoAP.Codec.validate_options/1` over three RFC 7252 messages with an
eight-byte token: a GET with Uri-Path, Uri-Query and Accept; a 2.05
notification with ETag, Observe, Content-Format, Max-Age, Block2 and Size2
and a 256-byte payload; and a Block1 PUT with 14 options, including
extended option deltas for Size1 and Request-Tag, and a 1024-byte payload
close to the 1152-byte datagram limit. Encoding and decoding include header,
option ordering and length checks; option validation adds the critical,
repeat and per-option length rules.


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



__Input: 2.05 notification, 6 options, 256-byte payload__

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
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap; text-align: right">3.72 M</td>
    <td style="white-space: nowrap; text-align: right">268.96 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;880.37%</td>
    <td style="white-space: nowrap; text-align: right">250 ns</td>
    <td style="white-space: nowrap; text-align: right">375 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap; text-align: right">1.80 M</td>
    <td style="white-space: nowrap; text-align: right">556.49 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1064.37%</td>
    <td style="white-space: nowrap; text-align: right">416 ns</td>
    <td style="white-space: nowrap; text-align: right">1750 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap; text-align: right">1.66 M</td>
    <td style="white-space: nowrap; text-align: right">602.95 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;914.41%</td>
    <td style="white-space: nowrap; text-align: right">542 ns</td>
    <td style="white-space: nowrap; text-align: right">750 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap;text-align: right">3.72 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap; text-align: right">1.80 M</td>
    <td style="white-space: nowrap; text-align: right">2.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap; text-align: right">1.66 M</td>
    <td style="white-space: nowrap; text-align: right">2.24x</td>
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
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap">1.41 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap">1.81 KB</td>
    <td>1.29x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap">0.87 KB</td>
    <td>0.62x</td>
  </tr>
</table>



__Input: GET request, 4 options__

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
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap; text-align: right">6.14 M</td>
    <td style="white-space: nowrap; text-align: right">162.98 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;348.59%</td>
    <td style="white-space: nowrap; text-align: right">150 ns</td>
    <td style="white-space: nowrap; text-align: right">262.50 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap; text-align: right">3.96 M</td>
    <td style="white-space: nowrap; text-align: right">252.80 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2054.38%</td>
    <td style="white-space: nowrap; text-align: right">209 ns</td>
    <td style="white-space: nowrap; text-align: right">334 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap; text-align: right">2.28 M</td>
    <td style="white-space: nowrap; text-align: right">438.58 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1251.26%</td>
    <td style="white-space: nowrap; text-align: right">416 ns</td>
    <td style="white-space: nowrap; text-align: right">542 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap;text-align: right">6.14 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap; text-align: right">3.96 M</td>
    <td style="white-space: nowrap; text-align: right">1.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap; text-align: right">2.28 M</td>
    <td style="white-space: nowrap; text-align: right">2.69x</td>
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
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap">992 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap">1280 B</td>
    <td>1.29x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap">792 B</td>
    <td>0.8x</td>
  </tr>
</table>



__Input: PUT Block1, 14 options, 1024-byte payload__

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
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap; text-align: right">1.80 M</td>
    <td style="white-space: nowrap; text-align: right">554.86 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;566.33%</td>
    <td style="white-space: nowrap; text-align: right">500 ns</td>
    <td style="white-space: nowrap; text-align: right">916 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap; text-align: right">1.15 M</td>
    <td style="white-space: nowrap; text-align: right">870.07 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;621.47%</td>
    <td style="white-space: nowrap; text-align: right">708 ns</td>
    <td style="white-space: nowrap; text-align: right">3334 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap; text-align: right">0.79 M</td>
    <td style="white-space: nowrap; text-align: right">1263.16 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;268.55%</td>
    <td style="white-space: nowrap; text-align: right">1208 ns</td>
    <td style="white-space: nowrap; text-align: right">1625 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap;text-align: right">1.80 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap; text-align: right">1.15 M</td>
    <td style="white-space: nowrap; text-align: right">1.57x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap; text-align: right">0.79 M</td>
    <td style="white-space: nowrap; text-align: right">2.28x</td>
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
    <td style="white-space: nowrap">decode</td>
    <td style="white-space: nowrap">3.28 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode</td>
    <td style="white-space: nowrap">3.69 KB</td>
    <td>1.12x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate options</td>
    <td style="white-space: nowrap">1.24 KB</td>
    <td>0.38x</td>
  </tr>
</table>