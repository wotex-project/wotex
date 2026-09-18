# Typed BACnet value conversion

`Wotex.BACnet.Value` over a `bacv:Real` present-value and `bacv:String`
values of 64 bytes and 1 KiB. `encode/2` checks the declared scalar type
and builds the BACstack application-tag encoding; `validate_write/1` is the
admission every native write passes, which bounds the value structure,
re-encodes the tag and checks its character set; `result/1` projects the
value and its BACnet type for a Runtime result. Strings are retained as
`Wotex.BACnet.CharacterString` values with character set 0 (UTF-8).


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
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap; text-align: right">32179.26 K</td>
    <td style="white-space: nowrap; text-align: right">0.0311 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;684.79%</td>
    <td style="white-space: nowrap; text-align: right">0.0292 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.0417 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap; text-align: right">541.25 K</td>
    <td style="white-space: nowrap; text-align: right">1.85 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;216.14%</td>
    <td style="white-space: nowrap; text-align: right">1.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap; text-align: right">136.83 K</td>
    <td style="white-space: nowrap; text-align: right">7.31 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.20%</td>
    <td style="white-space: nowrap; text-align: right">7.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">14.08 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap;text-align: right">32179.26 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap; text-align: right">541.25 K</td>
    <td style="white-space: nowrap; text-align: right">59.45x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap; text-align: right">136.83 K</td>
    <td style="white-space: nowrap; text-align: right">235.18x</td>
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
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap">24 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap">224 B</td>
    <td>9.33x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap">960 B</td>
    <td>40.0x</td>
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
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap; text-align: right">74.90 M</td>
    <td style="white-space: nowrap; text-align: right">13.35 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;708.61%</td>
    <td style="white-space: nowrap; text-align: right">12.91 ns</td>
    <td style="white-space: nowrap; text-align: right">16.25 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap; text-align: right">5.11 M</td>
    <td style="white-space: nowrap; text-align: right">195.88 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2039.27%</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
    <td style="white-space: nowrap; text-align: right">292 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap; text-align: right">1.42 M</td>
    <td style="white-space: nowrap; text-align: right">705.22 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1012.60%</td>
    <td style="white-space: nowrap; text-align: right">584 ns</td>
    <td style="white-space: nowrap; text-align: right">834 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap;text-align: right">74.90 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap; text-align: right">5.11 M</td>
    <td style="white-space: nowrap; text-align: right">14.67x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap; text-align: right">1.42 M</td>
    <td style="white-space: nowrap; text-align: right">52.82x</td>
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
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap">24 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap">224 B</td>
    <td>9.33x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap">960 B</td>
    <td>40.0x</td>
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
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap; text-align: right">73.42 M</td>
    <td style="white-space: nowrap; text-align: right">13.62 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3026.70%</td>
    <td style="white-space: nowrap; text-align: right">12.50 ns</td>
    <td style="white-space: nowrap; text-align: right">20.80 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap; text-align: right">19.14 M</td>
    <td style="white-space: nowrap; text-align: right">52.26 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1743.72%</td>
    <td style="white-space: nowrap; text-align: right">45.90 ns</td>
    <td style="white-space: nowrap; text-align: right">62.50 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap; text-align: right">4.83 M</td>
    <td style="white-space: nowrap; text-align: right">206.89 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3008.09%</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
    <td style="white-space: nowrap; text-align: right">333 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap;text-align: right">73.42 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap; text-align: right">19.14 M</td>
    <td style="white-space: nowrap; text-align: right">3.84x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap; text-align: right">4.83 M</td>
    <td style="white-space: nowrap; text-align: right">15.19x</td>
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
    <td style="white-space: nowrap">project result</td>
    <td style="white-space: nowrap">56 B</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode declared type</td>
    <td style="white-space: nowrap">136 B</td>
    <td>2.43x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">validate native write</td>
    <td style="white-space: nowrap">584 B</td>
    <td>10.43x</td>
  </tr>
</table>