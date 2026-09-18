# Thread Operational Dataset TLVs

`Wotex.Thread.Dataset.decode/1`, `encode/1` (which revalidates the
complete value by decoding it again) and `complete?/2` over a complete
Active Dataset of 10 TLVs (102 bytes), a complete Pending Dataset of 12
TLVs (118 bytes) and that Active Dataset padded with eight unknown TLVs to
the 254-byte limit.


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



__Input: 254 bytes with 8 unknown TLVs__

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
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap; text-align: right">896.24 K</td>
    <td style="white-space: nowrap; text-align: right">1.12 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;458.52%</td>
    <td style="white-space: nowrap; text-align: right">0.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap; text-align: right">613.03 K</td>
    <td style="white-space: nowrap; text-align: right">1.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;303.28%</td>
    <td style="white-space: nowrap; text-align: right">1.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap; text-align: right">574.10 K</td>
    <td style="white-space: nowrap; text-align: right">1.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;363.71%</td>
    <td style="white-space: nowrap; text-align: right">1.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.92 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap;text-align: right">896.24 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap; text-align: right">613.03 K</td>
    <td style="white-space: nowrap; text-align: right">1.46x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap; text-align: right">574.10 K</td>
    <td style="white-space: nowrap; text-align: right">1.56x</td>
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
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap">4.99 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap">6.68 KB</td>
    <td>1.34x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap">6.70 KB</td>
    <td>1.34x</td>
  </tr>
</table>



__Input: Active Dataset (10 TLVs)__

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
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap; text-align: right">1246.64 K</td>
    <td style="white-space: nowrap; text-align: right">0.80 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;659.08%</td>
    <td style="white-space: nowrap; text-align: right">0.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap; text-align: right">911.39 K</td>
    <td style="white-space: nowrap; text-align: right">1.10 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;534.30%</td>
    <td style="white-space: nowrap; text-align: right">0.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap; text-align: right">833.67 K</td>
    <td style="white-space: nowrap; text-align: right">1.20 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;487.39%</td>
    <td style="white-space: nowrap; text-align: right">0.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.63 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap;text-align: right">1246.64 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap; text-align: right">911.39 K</td>
    <td style="white-space: nowrap; text-align: right">1.37x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap; text-align: right">833.67 K</td>
    <td style="white-space: nowrap; text-align: right">1.5x</td>
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
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap">2.53 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap">3.16 KB</td>
    <td>1.25x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap">3.10 KB</td>
    <td>1.23x</td>
  </tr>
</table>



__Input: Pending Dataset (12 TLVs)__

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
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap; text-align: right">1123.36 K</td>
    <td style="white-space: nowrap; text-align: right">0.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;701.07%</td>
    <td style="white-space: nowrap; text-align: right">0.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap; text-align: right">829.94 K</td>
    <td style="white-space: nowrap; text-align: right">1.20 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;568.87%</td>
    <td style="white-space: nowrap; text-align: right">1 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap; text-align: right">745.35 K</td>
    <td style="white-space: nowrap; text-align: right">1.34 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;428.09%</td>
    <td style="white-space: nowrap; text-align: right">1.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.04 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap;text-align: right">1123.36 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap; text-align: right">829.94 K</td>
    <td style="white-space: nowrap; text-align: right">1.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap; text-align: right">745.35 K</td>
    <td style="white-space: nowrap; text-align: right">1.51x</td>
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
    <td style="white-space: nowrap">decode TLVs</td>
    <td style="white-space: nowrap">3.06 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode TLVs</td>
    <td style="white-space: nowrap">3.77 KB</td>
    <td>1.23x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">check required TLVs</td>
    <td style="white-space: nowrap">4 KB</td>
    <td>1.31x</td>
  </tr>
</table>