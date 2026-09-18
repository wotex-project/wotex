# Form mapping and message admission

`Wotex.BACnet.Mapping.command/4` over `bacnet://1234/2,1/<property>` Forms
for a Real present-value and CharacterString object-name (64 bytes) and
description (1 KiB), each with a `bacv:hasDataType` selector and an
unknown extension term. Mapping checks the operation and type selector,
parses the device, object and Property address, and for `writeproperty`
encodes the input as the declared type and validates it as a native write.
`Wotex.BACnet.Address.validate_message/1` is the facade's admission of the
mapped write message before a client is called.


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
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">486.14 K</td>
    <td style="white-space: nowrap; text-align: right">2.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;392.81%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap; text-align: right">135.71 K</td>
    <td style="white-space: nowrap; text-align: right">7.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;40.94%</td>
    <td style="white-space: nowrap; text-align: right">7.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">14.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">88.08 K</td>
    <td style="white-space: nowrap; text-align: right">11.35 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;25.45%</td>
    <td style="white-space: nowrap; text-align: right">10.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">18.88 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap;text-align: right">486.14 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap; text-align: right">135.71 K</td>
    <td style="white-space: nowrap; text-align: right">3.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">88.08 K</td>
    <td style="white-space: nowrap; text-align: right">5.52x</td>
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
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap">2.80 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap">1.05 KB</td>
    <td>0.38x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap">4.27 KB</td>
    <td>1.52x</td>
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
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap; text-align: right">1391.04 K</td>
    <td style="white-space: nowrap; text-align: right">0.72 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;761.75%</td>
    <td style="white-space: nowrap; text-align: right">0.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">485.16 K</td>
    <td style="white-space: nowrap; text-align: right">2.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;374.57%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">333.03 K</td>
    <td style="white-space: nowrap; text-align: right">3.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;296.42%</td>
    <td style="white-space: nowrap; text-align: right">2.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">6.75 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">1391.04 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">485.16 K</td>
    <td style="white-space: nowrap; text-align: right">2.87x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">333.03 K</td>
    <td style="white-space: nowrap; text-align: right">4.18x</td>
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
    <td style="white-space: nowrap">1.05 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap">2.73 KB</td>
    <td>2.59x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap">4.20 KB</td>
    <td>3.99x</td>
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
    <td style="white-space: nowrap">admit mapped write message</td>
    <td style="white-space: nowrap; text-align: right">4293.32 K</td>
    <td style="white-space: nowrap; text-align: right">0.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1643.55%</td>
    <td style="white-space: nowrap; text-align: right">0.167 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.38 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">490.67 K</td>
    <td style="white-space: nowrap; text-align: right">2.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;387.25%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">422.90 K</td>
    <td style="white-space: nowrap; text-align: right">2.36 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;336.45%</td>
    <td style="white-space: nowrap; text-align: right">2 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.29 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">4293.32 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap; text-align: right">490.67 K</td>
    <td style="white-space: nowrap; text-align: right">8.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap; text-align: right">422.90 K</td>
    <td style="white-space: nowrap; text-align: right">10.15x</td>
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
    <td style="white-space: nowrap">0.69 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map readproperty Form</td>
    <td style="white-space: nowrap">2.80 KB</td>
    <td>4.08x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">map writeproperty Form</td>
    <td style="white-space: nowrap">3.82 KB</td>
    <td>5.56x</td>
  </tr>
</table>