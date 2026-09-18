# Bounded decoding and canonical encoding

`WotexContinuum.Codec` over an `observation_proposal` at wire schema 2.0.0
with a nested `execution_scope` and `mode`, whose Property value is a scalar
or a sampled series of 64 or 1,024 numbers. Decoding applies the default
`WotexContinuum.Limits` through `Wotex.JSON.decode/2` and then constructs
the value; both encodings revalidate the value first, and the canonical
form orders object members by UTF-8 bytes. `WotexContinuum.from_map/1`
measures construction from an already decoded string-keyed map.


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



__Input: 1,024-sample value__

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
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap; text-align: right">8.41 K</td>
    <td style="white-space: nowrap; text-align: right">118.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.64%</td>
    <td style="white-space: nowrap; text-align: right">116.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">170.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap; text-align: right">6.07 K</td>
    <td style="white-space: nowrap; text-align: right">164.77 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.62%</td>
    <td style="white-space: nowrap; text-align: right">161.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">223.44 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap; text-align: right">3.17 K</td>
    <td style="white-space: nowrap; text-align: right">315.26 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.12%</td>
    <td style="white-space: nowrap; text-align: right">307.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">417.22 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap; text-align: right">1.74 K</td>
    <td style="white-space: nowrap; text-align: right">576.16 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.11%</td>
    <td style="white-space: nowrap; text-align: right">575.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">667.88 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap;text-align: right">8.41 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap; text-align: right">6.07 K</td>
    <td style="white-space: nowrap; text-align: right">1.39x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap; text-align: right">3.17 K</td>
    <td style="white-space: nowrap; text-align: right">2.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap; text-align: right">1.74 K</td>
    <td style="white-space: nowrap; text-align: right">4.84x</td>
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
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap">409.82 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap">474.02 KB</td>
    <td>1.16x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap">777.01 KB</td>
    <td>1.9x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap">1144.53 KB</td>
    <td>2.79x</td>
  </tr>
</table>



__Input: 64-sample value__

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
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap; text-align: right">75.56 K</td>
    <td style="white-space: nowrap; text-align: right">13.24 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;35.27%</td>
    <td style="white-space: nowrap; text-align: right">12.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">36.38 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap; text-align: right">53.86 K</td>
    <td style="white-space: nowrap; text-align: right">18.57 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;27.34%</td>
    <td style="white-space: nowrap; text-align: right">16.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">40 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap; text-align: right">26.97 K</td>
    <td style="white-space: nowrap; text-align: right">37.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.73%</td>
    <td style="white-space: nowrap; text-align: right">37.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">48.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap; text-align: right">19.77 K</td>
    <td style="white-space: nowrap; text-align: right">50.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.58%</td>
    <td style="white-space: nowrap; text-align: right">51.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">63.99 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap;text-align: right">75.56 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap; text-align: right">53.86 K</td>
    <td style="white-space: nowrap; text-align: right">1.4x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap; text-align: right">26.97 K</td>
    <td style="white-space: nowrap; text-align: right">2.8x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap; text-align: right">19.77 K</td>
    <td style="white-space: nowrap; text-align: right">3.82x</td>
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
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap">42.20 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap">54.69 KB</td>
    <td>1.3x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap">95.19 KB</td>
    <td>2.26x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap">109.53 KB</td>
    <td>2.6x</td>
  </tr>
</table>



__Input: scalar value__

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
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap; text-align: right">141.05 K</td>
    <td style="white-space: nowrap; text-align: right">7.09 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;72.41%</td>
    <td style="white-space: nowrap; text-align: right">6.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">14.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap; text-align: right">105.48 K</td>
    <td style="white-space: nowrap; text-align: right">9.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;27.04%</td>
    <td style="white-space: nowrap; text-align: right">8.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">17.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap; text-align: right">44.49 K</td>
    <td style="white-space: nowrap; text-align: right">22.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.56%</td>
    <td style="white-space: nowrap; text-align: right">21.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">31.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap; text-align: right">43.27 K</td>
    <td style="white-space: nowrap; text-align: right">23.11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.90%</td>
    <td style="white-space: nowrap; text-align: right">22.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">32.71 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap;text-align: right">141.05 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap; text-align: right">105.48 K</td>
    <td style="white-space: nowrap; text-align: right">1.34x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap; text-align: right">44.49 K</td>
    <td style="white-space: nowrap; text-align: right">3.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap; text-align: right">43.27 K</td>
    <td style="white-space: nowrap; text-align: right">3.26x</td>
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
    <td style="white-space: nowrap">WotexContinuum.from_map (decoded map)</td>
    <td style="white-space: nowrap">17.04 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode</td>
    <td style="white-space: nowrap">26.06 KB</td>
    <td>1.53x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.encode canonical</td>
    <td style="white-space: nowrap">49.13 KB</td>
    <td>2.88x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Codec.decode</td>
    <td style="white-space: nowrap">39.95 KB</td>
    <td>2.34x</td>
  </tr>
</table>