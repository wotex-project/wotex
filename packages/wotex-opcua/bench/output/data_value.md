# OPC UA DataValue and Variant conversion

`Wotex.OPCUA.Binary.encode_data_value/1` and `decode_data_value/1` (Part 6
DataValue with an explicit Variant, StatusCode and source and server
timestamps) and `Wotex.OPCUA.Value.native_result/1`, which projects the
native JSON DataValue of a Read or an observation onto a Runtime payload and
metadata. Inputs are a Double scalar, a flat array of 64 ByteStrings of
32 bytes each (Base64 in the native form) and a flat Double array at the
1024-element Variant ceiling.


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



__Input: ByteString array of 64 x 32 bytes__

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
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap; text-align: right">614.85 K</td>
    <td style="white-space: nowrap; text-align: right">1.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;288.29%</td>
    <td style="white-space: nowrap; text-align: right">1.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">6.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap; text-align: right">261.89 K</td>
    <td style="white-space: nowrap; text-align: right">3.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;126.07%</td>
    <td style="white-space: nowrap; text-align: right">3.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">11.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap; text-align: right">81.20 K</td>
    <td style="white-space: nowrap; text-align: right">12.32 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.90%</td>
    <td style="white-space: nowrap; text-align: right">11.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">30.88 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap;text-align: right">614.85 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap; text-align: right">261.89 K</td>
    <td style="white-space: nowrap; text-align: right">2.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap; text-align: right">81.20 K</td>
    <td style="white-space: nowrap; text-align: right">7.57x</td>
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
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap">8 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap">45.38 KB</td>
    <td>5.67x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap">29.22 KB</td>
    <td>3.65x</td>
  </tr>
</table>



__Input: Double array of 1024__

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
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap; text-align: right">168.80 K</td>
    <td style="white-space: nowrap; text-align: right">5.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;73.58%</td>
    <td style="white-space: nowrap; text-align: right">5.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">14.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap; text-align: right">85.92 K</td>
    <td style="white-space: nowrap; text-align: right">11.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;26.98%</td>
    <td style="white-space: nowrap; text-align: right">10.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">19 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap; text-align: right">20.25 K</td>
    <td style="white-space: nowrap; text-align: right">49.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.46%</td>
    <td style="white-space: nowrap; text-align: right">47.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">113.54 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap;text-align: right">168.80 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap; text-align: right">85.92 K</td>
    <td style="white-space: nowrap; text-align: right">1.96x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap; text-align: right">20.25 K</td>
    <td style="white-space: nowrap; text-align: right">8.33x</td>
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
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap">104.67 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap">81 KB</td>
    <td>0.77x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap">604.39 KB</td>
    <td>5.77x</td>
  </tr>
</table>



__Input: Double scalar__

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
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap; text-align: right">4.72 M</td>
    <td style="white-space: nowrap; text-align: right">212.06 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1955.45%</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
    <td style="white-space: nowrap; text-align: right">292 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap; text-align: right">3.32 M</td>
    <td style="white-space: nowrap; text-align: right">300.87 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;814.86%</td>
    <td style="white-space: nowrap; text-align: right">250 ns</td>
    <td style="white-space: nowrap; text-align: right">417 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap; text-align: right">2.86 M</td>
    <td style="white-space: nowrap; text-align: right">349.69 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1448.67%</td>
    <td style="white-space: nowrap; text-align: right">250 ns</td>
    <td style="white-space: nowrap; text-align: right">459 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap;text-align: right">4.72 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap; text-align: right">3.32 M</td>
    <td style="white-space: nowrap; text-align: right">1.42x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap; text-align: right">2.86 M</td>
    <td style="white-space: nowrap; text-align: right">1.65x</td>
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
    <td style="white-space: nowrap">project native DataValue</td>
    <td style="white-space: nowrap">640 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode DataValue</td>
    <td style="white-space: nowrap">2160 B</td>
    <td>3.38x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode DataValue</td>
    <td style="white-space: nowrap">888 B</td>
    <td>1.39x</td>
  </tr>
</table>