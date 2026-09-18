# UUID normalization and characteristic identity

`Wotex.BLE.UUID.normalize/1`, `encode/1` and `decode/1` for the Bluetooth
SIG Temperature characteristic (0x2A6E) as an integer and as `0x` text,
and for a synthetic 128-bit vendor UUID in canonical text. `encode/1`
always yields the 16-octet ATT form; `decode/1` takes the two-octet SIG
form or the 16-octet vendor form. `Wotex.BLE.Characteristic.address/1`
validates a discovered characteristic (both UUIDs, both D-Bus object paths,
three flags, handle and generation) and returns its generation-bound
`Wotex.BLE.Address`.


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



__Input: 128-bit text__

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
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">2231.28 K</td>
    <td style="white-space: nowrap; text-align: right">0.45 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1168.13%</td>
    <td style="white-space: nowrap; text-align: right">0.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap; text-align: right">790.73 K</td>
    <td style="white-space: nowrap; text-align: right">1.26 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;631.41%</td>
    <td style="white-space: nowrap; text-align: right">1.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">575.92 K</td>
    <td style="white-space: nowrap; text-align: right">1.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;453.22%</td>
    <td style="white-space: nowrap; text-align: right">1.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap; text-align: right">134.81 K</td>
    <td style="white-space: nowrap; text-align: right">7.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;88.14%</td>
    <td style="white-space: nowrap; text-align: right">6.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">23.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap;text-align: right">2231.28 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap; text-align: right">790.73 K</td>
    <td style="white-space: nowrap; text-align: right">2.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">575.92 K</td>
    <td style="white-space: nowrap; text-align: right">3.87x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap; text-align: right">134.81 K</td>
    <td style="white-space: nowrap; text-align: right">16.55x</td>
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
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap">1.53 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap">1.78 KB</td>
    <td>1.16x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap">2.89 KB</td>
    <td>1.89x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap">9.70 KB</td>
    <td>6.34x</td>
  </tr>
</table>



__Input: 16-bit integer__

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
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap; text-align: right">1.77 M</td>
    <td style="white-space: nowrap; text-align: right">0.57 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1093.82%</td>
    <td style="white-space: nowrap; text-align: right">0.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">1.68 M</td>
    <td style="white-space: nowrap; text-align: right">0.59 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;753.75%</td>
    <td style="white-space: nowrap; text-align: right">0.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">0.98 M</td>
    <td style="white-space: nowrap; text-align: right">1.02 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;656.39%</td>
    <td style="white-space: nowrap; text-align: right">0.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap; text-align: right">0.143 M</td>
    <td style="white-space: nowrap; text-align: right">6.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;171.27%</td>
    <td style="white-space: nowrap; text-align: right">5.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">26.58 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap;text-align: right">1.77 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">1.68 M</td>
    <td style="white-space: nowrap; text-align: right">1.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">0.98 M</td>
    <td style="white-space: nowrap; text-align: right">1.81x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap; text-align: right">0.143 M</td>
    <td style="white-space: nowrap; text-align: right">12.34x</td>
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
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap">1.77 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap">1.78 KB</td>
    <td>1.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap">2.90 KB</td>
    <td>1.63x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap">9.70 KB</td>
    <td>5.47x</td>
  </tr>
</table>



__Input: 16-bit text__

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
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">1.69 M</td>
    <td style="white-space: nowrap; text-align: right">0.59 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;759.07%</td>
    <td style="white-space: nowrap; text-align: right">0.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap; text-align: right">1.39 M</td>
    <td style="white-space: nowrap; text-align: right">0.72 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;743.28%</td>
    <td style="white-space: nowrap; text-align: right">0.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">0.84 M</td>
    <td style="white-space: nowrap; text-align: right">1.18 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;476.05%</td>
    <td style="white-space: nowrap; text-align: right">0.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap; text-align: right">0.148 M</td>
    <td style="white-space: nowrap; text-align: right">6.77 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;107.41%</td>
    <td style="white-space: nowrap; text-align: right">5.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">19.96 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap;text-align: right">1.69 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap; text-align: right">1.39 M</td>
    <td style="white-space: nowrap; text-align: right">1.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap; text-align: right">0.84 M</td>
    <td style="white-space: nowrap; text-align: right">2.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap; text-align: right">0.148 M</td>
    <td style="white-space: nowrap; text-align: right">11.45x</td>
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
    <td style="white-space: nowrap">decode ATT UUID</td>
    <td style="white-space: nowrap">1.78 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">normalize</td>
    <td style="white-space: nowrap">2.34 KB</td>
    <td>1.31x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ATT UUID</td>
    <td style="white-space: nowrap">3.46 KB</td>
    <td>1.94x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">admit discovered characteristic</td>
    <td style="white-space: nowrap">9.76 KB</td>
    <td>5.48x</td>
  </tr>
</table>