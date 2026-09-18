# Manifest construction and compatibility evaluation

A `continuum_manifest` that declares one, 16 or 128 capabilities and requires
each of them with `~> 2.0`. `WotexContinuum.Manifest.from_map/1` constructs
and validates the manifest from its decoded map.
`WotexContinuum.Manifest.compatible_with?/3` evaluates schema version 2.0.7
against consumer capabilities at version 2.4.1, which meet every requirement.
`WotexContinuum.Compatibility.evaluate/3` runs against capabilities at
version 1.9.0 and is expected to return one `capability_version` mismatch
per requirement, the complete report the contract promises.


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



__Input: 1 capability__

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
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap; text-align: right">477.04 K</td>
    <td style="white-space: nowrap; text-align: right">2.10 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;261.77%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">21.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap; text-align: right">421.59 K</td>
    <td style="white-space: nowrap; text-align: right">2.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;263.16%</td>
    <td style="white-space: nowrap; text-align: right">1.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">22.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap; text-align: right">103.18 K</td>
    <td style="white-space: nowrap; text-align: right">9.69 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;69.64%</td>
    <td style="white-space: nowrap; text-align: right">8.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">27.79 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap;text-align: right">477.04 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap; text-align: right">421.59 K</td>
    <td style="white-space: nowrap; text-align: right">1.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap; text-align: right">103.18 K</td>
    <td style="white-space: nowrap; text-align: right">4.62x</td>
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
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap">4.32 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap">4.21 KB</td>
    <td>0.97x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap">23.37 KB</td>
    <td>5.41x</td>
  </tr>
</table>



__Input: 128 capabilities__

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
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap; text-align: right">6.63 K</td>
    <td style="white-space: nowrap; text-align: right">150.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.29%</td>
    <td style="white-space: nowrap; text-align: right">148.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">180.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap; text-align: right">6.51 K</td>
    <td style="white-space: nowrap; text-align: right">153.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.07%</td>
    <td style="white-space: nowrap; text-align: right">150.31 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">189.53 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap; text-align: right">1.96 K</td>
    <td style="white-space: nowrap; text-align: right">509.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.15%</td>
    <td style="white-space: nowrap; text-align: right">505.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">668.99 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap;text-align: right">6.63 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap; text-align: right">6.51 K</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap; text-align: right">1.96 K</td>
    <td style="white-space: nowrap; text-align: right">3.38x</td>
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
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap">274.57 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap">285.59 KB</td>
    <td>1.04x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap">1372.71 KB</td>
    <td>5.0x</td>
  </tr>
</table>



__Input: 16 capabilities__

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
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap; text-align: right">51.30 K</td>
    <td style="white-space: nowrap; text-align: right">19.49 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;36.62%</td>
    <td style="white-space: nowrap; text-align: right">16.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">45.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap; text-align: right">49.26 K</td>
    <td style="white-space: nowrap; text-align: right">20.30 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;30.30%</td>
    <td style="white-space: nowrap; text-align: right">18.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">45.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap; text-align: right">14.58 K</td>
    <td style="white-space: nowrap; text-align: right">68.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.80%</td>
    <td style="white-space: nowrap; text-align: right">68.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">87.61 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap;text-align: right">51.30 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap; text-align: right">49.26 K</td>
    <td style="white-space: nowrap; text-align: right">1.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap; text-align: right">14.58 K</td>
    <td style="white-space: nowrap; text-align: right">3.52x</td>
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
    <td style="white-space: nowrap">compatible_with? (every requirement met)</td>
    <td style="white-space: nowrap">35.97 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Compatibility.evaluate (every requirement mismatched)</td>
    <td style="white-space: nowrap">37.37 KB</td>
    <td>1.04x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Manifest.from_map</td>
    <td style="white-space: nowrap">181.38 KB</td>
    <td>5.04x</td>
  </tr>
</table>