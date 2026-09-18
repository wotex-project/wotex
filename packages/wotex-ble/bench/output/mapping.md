# Form mapping and message admission

`Wotex.BLE.Mapping.command/4` over `ble://peer/<service>/<characteristic>`
Forms with explicit `wotex:bleValueType` and `wotex:bleByteOrder` selectors
and an unknown extension term: the Environmental Sensing Temperature
characteristic (SIG UUIDs 0x181A and 0x2A6E) as `int16` and as `float64`,
and 512 bytes of `utf8` text on a characteristic with 128-bit vendor UUIDs.
Mapping revalidates the Form for its context, checks the operation and
selectors, parses the device and both UUIDs from the href, and for
`writeproperty` encodes the input with the selected codec.
`Wotex.BLE.Address.validate_message/1` is the facade's admission of the
mapped write message, including the 512-byte value limit.


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
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap; text-align: right">399.25 K</td>
    <td style="white-space: nowrap; text-align: right">2.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;317.26%</td>
    <td style="white-space: nowrap; text-align: right">2.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">49.62 K</td>
    <td style="white-space: nowrap; text-align: right">20.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.60%</td>
    <td style="white-space: nowrap; text-align: right">18.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">35.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">47.72 K</td>
    <td style="white-space: nowrap; text-align: right">20.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;22.00%</td>
    <td style="white-space: nowrap; text-align: right">19.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">41.96 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap;text-align: right">399.25 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">49.62 K</td>
    <td style="white-space: nowrap; text-align: right">8.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">47.72 K</td>
    <td style="white-space: nowrap; text-align: right">8.37x</td>
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
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap">3.75 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap">35.14 KB</td>
    <td>9.37x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap">35.27 KB</td>
    <td>9.41x</td>
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
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap; text-align: right">390.19 K</td>
    <td style="white-space: nowrap; text-align: right">2.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;381.60%</td>
    <td style="white-space: nowrap; text-align: right">2.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">52.93 K</td>
    <td style="white-space: nowrap; text-align: right">18.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.45%</td>
    <td style="white-space: nowrap; text-align: right">17.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">31.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">52.25 K</td>
    <td style="white-space: nowrap; text-align: right">19.14 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.61%</td>
    <td style="white-space: nowrap; text-align: right">17.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">33.58 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap;text-align: right">390.19 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">52.93 K</td>
    <td style="white-space: nowrap; text-align: right">7.37x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">52.25 K</td>
    <td style="white-space: nowrap; text-align: right">7.47x</td>
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
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap">3.75 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap">35.70 KB</td>
    <td>9.52x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap">35.31 KB</td>
    <td>9.42x</td>
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
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap; text-align: right">388.50 K</td>
    <td style="white-space: nowrap; text-align: right">2.57 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;377.33%</td>
    <td style="white-space: nowrap; text-align: right">2.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5.29 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">52.70 K</td>
    <td style="white-space: nowrap; text-align: right">18.98 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.70%</td>
    <td style="white-space: nowrap; text-align: right">17.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">33.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">52.65 K</td>
    <td style="white-space: nowrap; text-align: right">18.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.49%</td>
    <td style="white-space: nowrap; text-align: right">17.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">33.13 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap;text-align: right">388.50 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">52.70 K</td>
    <td style="white-space: nowrap; text-align: right">7.37x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">52.65 K</td>
    <td style="white-space: nowrap; text-align: right">7.38x</td>
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
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap">3.75 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap">35.52 KB</td>
    <td>9.47x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap">35.31 KB</td>
    <td>9.42x</td>
  </tr>
</table>