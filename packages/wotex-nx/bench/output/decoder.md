# Decoding numerical output into inert values

`Wotex.Nx.Decoder.decode/3` of an `f32` tensor on the default
`Nx.BinaryBackend` into an inert `Wotex.Nx.Prediction` or
`Wotex.Nx.Observation`, for a scalar `number` DataSchema and fixed-size
arrays of 16 and 256 numbers. Decoding rechecks the `Wotex.Nx.OutputSchema`,
the tensor shape and dtype, reads the tensor back to host values and
validates them against the DataSchema before building the value.


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



__Input: 16-step forecast__

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
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap; text-align: right">74.76 K</td>
    <td style="white-space: nowrap; text-align: right">13.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.18%</td>
    <td style="white-space: nowrap; text-align: right">12.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">21.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap; text-align: right">67.01 K</td>
    <td style="white-space: nowrap; text-align: right">14.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.29%</td>
    <td style="white-space: nowrap; text-align: right">14.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">23.75 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap;text-align: right">74.76 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap; text-align: right">67.01 K</td>
    <td style="white-space: nowrap; text-align: right">1.12x</td>
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
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap">33.13 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap">36.05 KB</td>
    <td>1.09x</td>
  </tr>
</table>



__Input: 256-step forecast__

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
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap; text-align: right">24.23 K</td>
    <td style="white-space: nowrap; text-align: right">41.27 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.73%</td>
    <td style="white-space: nowrap; text-align: right">40.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">54.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap; text-align: right">24.07 K</td>
    <td style="white-space: nowrap; text-align: right">41.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.98%</td>
    <td style="white-space: nowrap; text-align: right">41.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">55.79 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap;text-align: right">24.23 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap; text-align: right">24.07 K</td>
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
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap">192.51 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap">195.42 KB</td>
    <td>1.02x</td>
  </tr>
</table>



__Input: scalar__

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
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap; text-align: right">135.46 K</td>
    <td style="white-space: nowrap; text-align: right">7.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;74.22%</td>
    <td style="white-space: nowrap; text-align: right">6.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">20.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap; text-align: right">132.22 K</td>
    <td style="white-space: nowrap; text-align: right">7.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;71.11%</td>
    <td style="white-space: nowrap; text-align: right">6.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">19.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap;text-align: right">135.46 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap; text-align: right">132.22 K</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
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
    <td style="white-space: nowrap">decode :prediction</td>
    <td style="white-space: nowrap">14.07 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">decode :observation</td>
    <td style="white-space: nowrap">17.09 KB</td>
    <td>1.21x</td>
  </tr>
</table>