# Keyset listing

`Wotex.Directory.list/3` over 400 registered Thing Descriptions with four
Properties each, for page limits of one, 50 (the default) and 200 (the
maximum). The continuation page decodes the opaque cursor issued by the
first page. The in-process repository builds each page from an immutable
sorted snapshot with `Wotex.Directory.Page.new/1`; page construction and
the Directory's own page validation both check every entry, including its
Thing Description, before the shared retrieval time is assigned.


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



__Input: 1 entry per page__

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
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap; text-align: right">8.65 K</td>
    <td style="white-space: nowrap; text-align: right">115.61 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.16%</td>
    <td style="white-space: nowrap; text-align: right">114.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">136.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap; text-align: right">8.00 K</td>
    <td style="white-space: nowrap; text-align: right">125.07 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.38%</td>
    <td style="white-space: nowrap; text-align: right">125.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">145.11 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap;text-align: right">8.65 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap; text-align: right">8.00 K</td>
    <td style="white-space: nowrap; text-align: right">1.08x</td>
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
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap">238.99 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap">247.03 KB</td>
    <td>1.03x</td>
  </tr>
</table>



__Input: 200 entries per page (maximum)__

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
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap; text-align: right">48.20</td>
    <td style="white-space: nowrap; text-align: right">20.75 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.90%</td>
    <td style="white-space: nowrap; text-align: right">20.75 ms</td>
    <td style="white-space: nowrap; text-align: right">21.30 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap; text-align: right">48.13</td>
    <td style="white-space: nowrap; text-align: right">20.78 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.90%</td>
    <td style="white-space: nowrap; text-align: right">20.79 ms</td>
    <td style="white-space: nowrap; text-align: right">21.20 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap;text-align: right">48.20</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap; text-align: right">48.13</td>
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
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap">45.39 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap">45.38 MB</td>
    <td>1.0x</td>
  </tr>
</table>



__Input: 50 entries per page (default)__

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
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap; text-align: right">193.39</td>
    <td style="white-space: nowrap; text-align: right">5.17 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.49%</td>
    <td style="white-space: nowrap; text-align: right">5.17 ms</td>
    <td style="white-space: nowrap; text-align: right">5.34 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap; text-align: right">191.06</td>
    <td style="white-space: nowrap; text-align: right">5.23 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.17%</td>
    <td style="white-space: nowrap; text-align: right">5.23 ms</td>
    <td style="white-space: nowrap; text-align: right">5.50 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap;text-align: right">193.39</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap; text-align: right">191.06</td>
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
    <td style="white-space: nowrap">first page</td>
    <td style="white-space: nowrap">11.35 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">continuation page (cursor)</td>
    <td style="white-space: nowrap">11.36 MB</td>
    <td>1.0x</td>
  </tr>
</table>