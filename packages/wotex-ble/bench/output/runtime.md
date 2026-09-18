# Runtime Property interactions through the BLE Transport

`Wotex.Runtime.ConsumedThing.read_property/3` and `write_property/4` with
`Wotex.BLE.Transport` on the one-shot profile and a pure in-process
`Wotex.BLE.Client` that returns the attribute bytes or the write
acknowledgement without a process, Port or D-Bus call. The values are an
`int16`, a `float64` and 512 bytes of `utf8` text. Each interaction covers
Form selection, `nosec` credential resolution, the Runtime request and
deadline budget, Form mapping and value encoding, session open and close,
facade admission, value decoding and the Runtime result, so it is the
complete in-process cost of one Property interaction apart from the GATT
procedure.


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



__Input: UTF-8 text, 512 bytes__

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
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">22.77 K</td>
    <td style="white-space: nowrap; text-align: right">43.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.06%</td>
    <td style="white-space: nowrap; text-align: right">44.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">58.29 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap; text-align: right">22.58 K</td>
    <td style="white-space: nowrap; text-align: right">44.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.75%</td>
    <td style="white-space: nowrap; text-align: right">43.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">57.64 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap;text-align: right">22.77 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap; text-align: right">22.58 K</td>
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
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap">74.64 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap">74.73 KB</td>
    <td>1.0x</td>
  </tr>
</table>



__Input: float64, 8 bytes__

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
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">23.93 K</td>
    <td style="white-space: nowrap; text-align: right">41.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.02%</td>
    <td style="white-space: nowrap; text-align: right">41.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">54.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap; text-align: right">23.80 K</td>
    <td style="white-space: nowrap; text-align: right">42.02 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.02%</td>
    <td style="white-space: nowrap; text-align: right">41.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">54.67 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap;text-align: right">23.93 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap; text-align: right">23.80 K</td>
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
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap">75.23 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">readproperty</td>
    <td style="white-space: nowrap">75.02 KB</td>
    <td>1.0x</td>
  </tr>
</table>



__Input: int16, 2 bytes__

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
    <td style="white-space: nowrap; text-align: right">23.89 K</td>
    <td style="white-space: nowrap; text-align: right">41.87 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.83%</td>
    <td style="white-space: nowrap; text-align: right">41.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">54.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">23.80 K</td>
    <td style="white-space: nowrap; text-align: right">42.01 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.18%</td>
    <td style="white-space: nowrap; text-align: right">42.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">56.42 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">23.89 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap; text-align: right">23.80 K</td>
    <td style="white-space: nowrap; text-align: right">1.0x</td>
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
    <td style="white-space: nowrap">74.68 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">writeproperty</td>
    <td style="white-space: nowrap">74.57 KB</td>
    <td>1.0x</td>
  </tr>
</table>