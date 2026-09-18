# CoRE Link Format discovery parsing

`Wotex.CoAP.LinkFormat.decode/2` over `/.well-known/core` bodies of four,
32 and 256 links (the default link limit), from 334 bytes to about 24 KiB.
The first link announces a Thing Description (`rt="wot.thing";ct=432`);
each further link carries quoted relation-type and interface lists, a
Content-Format, a size, the Observe flag and a quoted title with escaped
quotes. Every link target and attribute is syntax-checked under the default
body, link, attribute and token limits.


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



__Input: 256 links__

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
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap; text-align: right">316.81</td>
    <td style="white-space: nowrap; text-align: right">3.16 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.30%</td>
    <td style="white-space: nowrap; text-align: right">3.16 ms</td>
    <td style="white-space: nowrap; text-align: right">3.31 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap;text-align: right">316.81</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap">5.39 MB</td>
    <td>&nbsp;</td>
  </tr>
</table>



__Input: 32 links__

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
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap; text-align: right">2.55 K</td>
    <td style="white-space: nowrap; text-align: right">392.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.52%</td>
    <td style="white-space: nowrap; text-align: right">390.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">446.22 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap;text-align: right">2.55 K</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap">680.13 KB</td>
    <td>&nbsp;</td>
  </tr>
</table>



__Input: 4 links__

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
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap; text-align: right">23.48 K</td>
    <td style="white-space: nowrap; text-align: right">42.60 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.45%</td>
    <td style="white-space: nowrap; text-align: right">42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">57.75 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap;text-align: right">23.48 K</td>
    <td>&nbsp;</td>
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
    <td style="white-space: nowrap">decode with default limits</td>
    <td style="white-space: nowrap">75.54 KB</td>
    <td>&nbsp;</td>
  </tr>
</table>