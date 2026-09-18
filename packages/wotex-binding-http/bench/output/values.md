# HTTP field and message value construction

`Wotex.Binding.HTTP.Headers`, `Wotex.Binding.HTTP.Request` and
`Wotex.Binding.HTTP.Response` over field lists of four, 16 and 64 entries,
64 being the default field-count limit. Field names are mixed case, so
construction validates each token and value and lowercases the name.
`Request.new/5` also applies the field-count, aggregate field-byte and
URI limits before it normalizes the fields again; `merge/2` and `get/2`
compose static configuration fields with an already validated list.


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



__Input: 4 fields__

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
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap; text-align: right">2240.19 K</td>
    <td style="white-space: nowrap; text-align: right">0.45 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1315.22%</td>
    <td style="white-space: nowrap; text-align: right">0.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap; text-align: right">232.19 K</td>
    <td style="white-space: nowrap; text-align: right">4.31 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;332.22%</td>
    <td style="white-space: nowrap; text-align: right">3.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap; text-align: right">229.00 K</td>
    <td style="white-space: nowrap; text-align: right">4.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;325.54%</td>
    <td style="white-space: nowrap; text-align: right">3.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap; text-align: right">222.27 K</td>
    <td style="white-space: nowrap; text-align: right">4.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;494.16%</td>
    <td style="white-space: nowrap; text-align: right">3.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">8.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap; text-align: right">162.31 K</td>
    <td style="white-space: nowrap; text-align: right">6.16 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;194.42%</td>
    <td style="white-space: nowrap; text-align: right">5.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">24.04 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap;text-align: right">2240.19 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap; text-align: right">232.19 K</td>
    <td style="white-space: nowrap; text-align: right">9.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap; text-align: right">229.00 K</td>
    <td style="white-space: nowrap; text-align: right">9.78x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap; text-align: right">222.27 K</td>
    <td style="white-space: nowrap; text-align: right">10.08x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap; text-align: right">162.31 K</td>
    <td style="white-space: nowrap; text-align: right">13.8x</td>
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
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap">2.13 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap">4.01 KB</td>
    <td>1.89x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap">4.01 KB</td>
    <td>1.89x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap">4.09 KB</td>
    <td>1.92x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap">6.46 KB</td>
    <td>3.04x</td>
  </tr>
</table>



__Input: 16 fields__

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
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap; text-align: right">351.91 K</td>
    <td style="white-space: nowrap; text-align: right">2.84 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;172.48%</td>
    <td style="white-space: nowrap; text-align: right">2.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap; text-align: right">58.50 K</td>
    <td style="white-space: nowrap; text-align: right">17.09 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;48.41%</td>
    <td style="white-space: nowrap; text-align: right">14.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">68.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap; text-align: right">54.69 K</td>
    <td style="white-space: nowrap; text-align: right">18.28 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;46.82%</td>
    <td style="white-space: nowrap; text-align: right">15.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">70.31 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap; text-align: right">54.11 K</td>
    <td style="white-space: nowrap; text-align: right">18.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;45.48%</td>
    <td style="white-space: nowrap; text-align: right">15.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">70.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap; text-align: right">51.20 K</td>
    <td style="white-space: nowrap; text-align: right">19.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;37.22%</td>
    <td style="white-space: nowrap; text-align: right">17.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">51.92 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap;text-align: right">351.91 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap; text-align: right">58.50 K</td>
    <td style="white-space: nowrap; text-align: right">6.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap; text-align: right">54.69 K</td>
    <td style="white-space: nowrap; text-align: right">6.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap; text-align: right">54.11 K</td>
    <td style="white-space: nowrap; text-align: right">6.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap; text-align: right">51.20 K</td>
    <td style="white-space: nowrap; text-align: right">6.87x</td>
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
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap">12.23 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap">20.82 KB</td>
    <td>1.7x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap">21.02 KB</td>
    <td>1.72x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap">21.02 KB</td>
    <td>1.72x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap">23.58 KB</td>
    <td>1.93x</td>
  </tr>
</table>



__Input: 64 fields__

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
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap; text-align: right">35.36 K</td>
    <td style="white-space: nowrap; text-align: right">28.28 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.73%</td>
    <td style="white-space: nowrap; text-align: right">27.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">36.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap; text-align: right">13.47 K</td>
    <td style="white-space: nowrap; text-align: right">74.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.21%</td>
    <td style="white-space: nowrap; text-align: right">74.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">92.52 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap; text-align: right">12.92 K</td>
    <td style="white-space: nowrap; text-align: right">77.43 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.06%</td>
    <td style="white-space: nowrap; text-align: right">73.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">102.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap; text-align: right">12.89 K</td>
    <td style="white-space: nowrap; text-align: right">77.59 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.04%</td>
    <td style="white-space: nowrap; text-align: right">78.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">96.84 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap; text-align: right">12.57 K</td>
    <td style="white-space: nowrap; text-align: right">79.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.57%</td>
    <td style="white-space: nowrap; text-align: right">75.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">107.33 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap;text-align: right">35.36 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap; text-align: right">13.47 K</td>
    <td style="white-space: nowrap; text-align: right">2.62x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap; text-align: right">12.92 K</td>
    <td style="white-space: nowrap; text-align: right">2.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap; text-align: right">12.89 K</td>
    <td style="white-space: nowrap; text-align: right">2.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap; text-align: right">12.57 K</td>
    <td style="white-space: nowrap; text-align: right">2.81x</td>
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
    <td style="white-space: nowrap">Headers.merge/2 and get/2</td>
    <td style="white-space: nowrap">77.81 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Response.new/3</td>
    <td style="white-space: nowrap">93.63 KB</td>
    <td>1.2x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Headers.new/2 for a response</td>
    <td style="white-space: nowrap">93.56 KB</td>
    <td>1.2x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Request.new/5</td>
    <td style="white-space: nowrap">96.80 KB</td>
    <td>1.24x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Headers.new/2 for a request</td>
    <td style="white-space: nowrap">93.56 KB</td>
    <td>1.2x</td>
  </tr>
</table>