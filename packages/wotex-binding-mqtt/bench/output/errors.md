# Failure classification

The failure paths of `Wotex.Binding.MQTT.Transport` against an in-memory
client port. Each job asserts the code and retry class of the returned
`Wotex.Binding.MQTT.Error`: a publish the client refuses, a client that
raises, a client that returns an undeclared value, a 16-member value above
a 64-byte payload limit, a retained read whose request deadline has
elapsed, a read answered by a non-retained delivery, and a truncated JSON
delivery decoded by `decode_frame/3`.


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
    <td style="white-space: nowrap">elapsed read deadline (timeout)</td>
    <td style="white-space: nowrap; text-align: right">177.41 K</td>
    <td style="white-space: nowrap; text-align: right">5.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;87.40%</td>
    <td style="white-space: nowrap; text-align: right">5.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">11.29 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">non-retained read delivery (protocol)</td>
    <td style="white-space: nowrap; text-align: right">174.71 K</td>
    <td style="white-space: nowrap; text-align: right">5.72 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;114.46%</td>
    <td style="white-space: nowrap; text-align: right">5.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">12.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">payload above the limit (protocol)</td>
    <td style="white-space: nowrap; text-align: right">146.82 K</td>
    <td style="white-space: nowrap; text-align: right">6.81 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;75.98%</td>
    <td style="white-space: nowrap; text-align: right">6.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">20.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">truncated JSON delivery (protocol)</td>
    <td style="white-space: nowrap; text-align: right">64.40 K</td>
    <td style="white-space: nowrap; text-align: right">15.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.14%</td>
    <td style="white-space: nowrap; text-align: right">15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">22.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">refused publish (unavailable)</td>
    <td style="white-space: nowrap; text-align: right">30.60 K</td>
    <td style="white-space: nowrap; text-align: right">32.68 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.43%</td>
    <td style="white-space: nowrap; text-align: right">32.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">43.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">raising client (unavailable)</td>
    <td style="white-space: nowrap; text-align: right">30.42 K</td>
    <td style="white-space: nowrap; text-align: right">32.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.36%</td>
    <td style="white-space: nowrap; text-align: right">32.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">43.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invalid client return (protocol)</td>
    <td style="white-space: nowrap; text-align: right">30.39 K</td>
    <td style="white-space: nowrap; text-align: right">32.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.78%</td>
    <td style="white-space: nowrap; text-align: right">32.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">43.17 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">elapsed read deadline (timeout)</td>
    <td style="white-space: nowrap;text-align: right">177.41 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">non-retained read delivery (protocol)</td>
    <td style="white-space: nowrap; text-align: right">174.71 K</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">payload above the limit (protocol)</td>
    <td style="white-space: nowrap; text-align: right">146.82 K</td>
    <td style="white-space: nowrap; text-align: right">1.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">truncated JSON delivery (protocol)</td>
    <td style="white-space: nowrap; text-align: right">64.40 K</td>
    <td style="white-space: nowrap; text-align: right">2.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">refused publish (unavailable)</td>
    <td style="white-space: nowrap; text-align: right">30.60 K</td>
    <td style="white-space: nowrap; text-align: right">5.8x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">raising client (unavailable)</td>
    <td style="white-space: nowrap; text-align: right">30.42 K</td>
    <td style="white-space: nowrap; text-align: right">5.83x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">invalid client return (protocol)</td>
    <td style="white-space: nowrap; text-align: right">30.39 K</td>
    <td style="white-space: nowrap; text-align: right">5.84x</td>
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
    <td style="white-space: nowrap">elapsed read deadline (timeout)</td>
    <td style="white-space: nowrap">4.71 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">non-retained read delivery (protocol)</td>
    <td style="white-space: nowrap">4.82 KB</td>
    <td>1.02x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">payload above the limit (protocol)</td>
    <td style="white-space: nowrap">10.50 KB</td>
    <td>2.23x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">truncated JSON delivery (protocol)</td>
    <td style="white-space: nowrap">16.93 KB</td>
    <td>3.59x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">refused publish (unavailable)</td>
    <td style="white-space: nowrap">70.91 KB</td>
    <td>15.05x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">raising client (unavailable)</td>
    <td style="white-space: nowrap">71.19 KB</td>
    <td>15.11x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">invalid client return (protocol)</td>
    <td style="white-space: nowrap">70.91 KB</td>
    <td>15.05x</td>
  </tr>
</table>