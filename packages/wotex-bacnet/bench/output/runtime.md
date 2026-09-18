# Runtime Property interactions through the BACnet Transport

`Wotex.Runtime.ConsumedThing.read_property/3` and `write_property/4` with
`Wotex.BACnet.Transport` and a pure in-process `Wotex.BACnet.Client` that
returns the value or the write acknowledgement without a process or socket.
The values are a Real present-value and CharacterString values of 64 bytes
and 1 KiB. Each interaction covers Form selection, `nosec` credential
resolution, the Runtime request and deadline budget, Form mapping, session
open and close, facade admission, native value validation and the Runtime
result, so it is the complete in-process cost of one Property interaction
apart from the BACnet/IP exchange.


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



__Input: 1 KiB description__

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
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap; text-align: right">32.52 K</td>
    <td style="white-space: nowrap; text-align: right">30.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.64%</td>
    <td style="white-space: nowrap; text-align: right">30 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">44.38 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">25.07 K</td>
    <td style="white-space: nowrap; text-align: right">39.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.07%</td>
    <td style="white-space: nowrap; text-align: right">38.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">53.67 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap;text-align: right">32.52 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">25.07 K</td>
    <td style="white-space: nowrap; text-align: right">1.3x</td>
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
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap">34.28 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap">35.69 KB</td>
    <td>1.04x</td>
  </tr>
</table>



__Input: 64-byte object-name__

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
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap; text-align: right">42.24 K</td>
    <td style="white-space: nowrap; text-align: right">23.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.05%</td>
    <td style="white-space: nowrap; text-align: right">22.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">40.73 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">41.86 K</td>
    <td style="white-space: nowrap; text-align: right">23.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.21%</td>
    <td style="white-space: nowrap; text-align: right">22.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">38.79 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap;text-align: right">42.24 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">41.86 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
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
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap">34.28 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap">35.69 KB</td>
    <td>1.04x</td>
  </tr>
</table>



__Input: Real present-value__

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
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap; text-align: right">45.45 K</td>
    <td style="white-space: nowrap; text-align: right">22.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.22%</td>
    <td style="white-space: nowrap; text-align: right">21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">35.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">44.40 K</td>
    <td style="white-space: nowrap; text-align: right">22.52 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.04%</td>
    <td style="white-space: nowrap; text-align: right">21.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">36.33 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap;text-align: right">45.45 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">44.40 K</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
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
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap">33.79 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap">34.84 KB</td>
    <td>1.03x</td>
  </tr>
</table>