# RFC 7959 blockwise transfer

`Wotex.CoAP.Blockwise.run/4` with 512-byte blocks over 1 KiB, 16 KiB and
256 KiB bodies (two, 32 and 512 exchanges) against a pure in-process
exchange function that returns precomputed replies, so no socket or timer
is involved. The Block2 download validates every reply, its
representation identity (status, ETag, Content-Format) and Size2 before
appending; the Block1 upload splits the body and checks each 2.31 Continue
acknowledgement. `Wotex.CoAP.Block.append/4` alone isolates the bounded
sequential reassembly under the default 1 MiB body limit.


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



__Input: 1 KiB__

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
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap; text-align: right">5532.75 K</td>
    <td style="white-space: nowrap; text-align: right">0.181 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1833.74%</td>
    <td style="white-space: nowrap; text-align: right">0.166 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.29 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap; text-align: right">533.84 K</td>
    <td style="white-space: nowrap; text-align: right">1.87 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;312.78%</td>
    <td style="white-space: nowrap; text-align: right">1.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap; text-align: right">328.40 K</td>
    <td style="white-space: nowrap; text-align: right">3.05 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;195.24%</td>
    <td style="white-space: nowrap; text-align: right">2.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">7.88 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap;text-align: right">5532.75 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap; text-align: right">533.84 K</td>
    <td style="white-space: nowrap; text-align: right">10.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap; text-align: right">328.40 K</td>
    <td style="white-space: nowrap; text-align: right">16.85x</td>
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
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap">0.34 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap">7.75 KB</td>
    <td>22.55x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap">8.77 KB</td>
    <td>25.52x</td>
  </tr>
</table>



__Input: 16 KiB__

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
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap; text-align: right">462.67 K</td>
    <td style="white-space: nowrap; text-align: right">2.16 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;271.45%</td>
    <td style="white-space: nowrap; text-align: right">1.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap; text-align: right">26.67 K</td>
    <td style="white-space: nowrap; text-align: right">37.49 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;114.97%</td>
    <td style="white-space: nowrap; text-align: right">18.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">216.77 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap; text-align: right">12.15 K</td>
    <td style="white-space: nowrap; text-align: right">82.27 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;40.62%</td>
    <td style="white-space: nowrap; text-align: right">82.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">152.31 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap;text-align: right">462.67 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap; text-align: right">26.67 K</td>
    <td style="white-space: nowrap; text-align: right">17.34x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap; text-align: right">12.15 K</td>
    <td style="white-space: nowrap; text-align: right">38.07x</td>
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
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap">4.56 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap">81.81 KB</td>
    <td>17.93x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap">116.41 KB</td>
    <td>25.52x</td>
  </tr>
</table>



__Input: 256 KiB__

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
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap; text-align: right">17.17 K</td>
    <td style="white-space: nowrap; text-align: right">58.24 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;94.45%</td>
    <td style="white-space: nowrap; text-align: right">31.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">233.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap; text-align: right">1.96 K</td>
    <td style="white-space: nowrap; text-align: right">509.32 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.82%</td>
    <td style="white-space: nowrap; text-align: right">496.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">694.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap; text-align: right">1.18 K</td>
    <td style="white-space: nowrap; text-align: right">845.77 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.91%</td>
    <td style="white-space: nowrap; text-align: right">896.69 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1086.18 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap;text-align: right">17.17 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap; text-align: right">1.96 K</td>
    <td style="white-space: nowrap; text-align: right">8.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap; text-align: right">1.18 K</td>
    <td style="white-space: nowrap; text-align: right">14.52x</td>
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
    <td style="white-space: nowrap">Block.append/4 reassembly</td>
    <td style="white-space: nowrap">0.0704 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Block1 upload</td>
    <td style="white-space: nowrap">1.24 MB</td>
    <td>17.58x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Block2 download</td>
    <td style="white-space: nowrap">1.79 MB</td>
    <td>25.5x</td>
  </tr>
</table>