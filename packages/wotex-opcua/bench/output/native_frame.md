# OPC UA native JSON-line framing

`Wotex.OPCUA.Native.Frame` on the BEAM side of the native executable's
JSON-line protocol: `request/6` encodes and bounds one version-1 request
line, `classify/2` admits one output line under the IPC limits and reads
its correlation, and `response/5` admits the line again and validates the
operation's result. Inputs are a Read of a Double DataValue, one Browse
page of 64 typed references and a Session open whose request carries
synthetic credential envelopes of typical DER sizes and whose response
carries a NamespaceArray of 32 URIs.


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



__Input: browse (64 references)__

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
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap; text-align: right">159.45 K</td>
    <td style="white-space: nowrap; text-align: right">6.27 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;64.60%</td>
    <td style="white-space: nowrap; text-align: right">5.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">12.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap; text-align: right">1.70 K</td>
    <td style="white-space: nowrap; text-align: right">587.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.42%</td>
    <td style="white-space: nowrap; text-align: right">579.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">668.07 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap; text-align: right">1.33 K</td>
    <td style="white-space: nowrap; text-align: right">750.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.21%</td>
    <td style="white-space: nowrap; text-align: right">746.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">828.67 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap;text-align: right">159.45 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap; text-align: right">1.70 K</td>
    <td style="white-space: nowrap; text-align: right">93.67x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap; text-align: right">1.33 K</td>
    <td style="white-space: nowrap; text-align: right">119.61x</td>
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
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap">15.17 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap">802.76 KB</td>
    <td>52.91x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap">1043.88 KB</td>
    <td>68.8x</td>
  </tr>
</table>



__Input: open (32 namespaces)__

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
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap; text-align: right">51.73 K</td>
    <td style="white-space: nowrap; text-align: right">19.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.05%</td>
    <td style="white-space: nowrap; text-align: right">18.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">29.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap; text-align: right">38.04 K</td>
    <td style="white-space: nowrap; text-align: right">26.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.98%</td>
    <td style="white-space: nowrap; text-align: right">25.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">35.71 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap; text-align: right">30.62 K</td>
    <td style="white-space: nowrap; text-align: right">32.66 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.98%</td>
    <td style="white-space: nowrap; text-align: right">31.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">44.13 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap;text-align: right">51.73 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap; text-align: right">38.04 K</td>
    <td style="white-space: nowrap; text-align: right">1.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap; text-align: right">30.62 K</td>
    <td style="white-space: nowrap; text-align: right">1.69x</td>
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
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap">30.16 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap">38.91 KB</td>
    <td>1.29x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap">34.01 KB</td>
    <td>1.13x</td>
  </tr>
</table>



__Input: read (Double DataValue)__

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
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap; text-align: right">234.72 K</td>
    <td style="white-space: nowrap; text-align: right">4.26 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;100.73%</td>
    <td style="white-space: nowrap; text-align: right">3.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">9.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap; text-align: right">169.70 K</td>
    <td style="white-space: nowrap; text-align: right">5.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;70.83%</td>
    <td style="white-space: nowrap; text-align: right">5.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">13.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap; text-align: right">134.84 K</td>
    <td style="white-space: nowrap; text-align: right">7.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;46.91%</td>
    <td style="white-space: nowrap; text-align: right">6.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">22.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap;text-align: right">234.72 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap; text-align: right">169.70 K</td>
    <td style="white-space: nowrap; text-align: right">1.38x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap; text-align: right">134.84 K</td>
    <td style="white-space: nowrap; text-align: right">1.74x</td>
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
    <td style="white-space: nowrap">encode request line</td>
    <td style="white-space: nowrap">10.72 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">classify output line</td>
    <td style="white-space: nowrap">10.66 KB</td>
    <td>0.99x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode correlated response</td>
    <td style="white-space: nowrap">12.78 KB</td>
    <td>1.19x</td>
  </tr>
</table>