# Form and binding-profile selection

`Wotex.Runtime.FormSelector.select/5` and `select_thing/3` against two
binding profiles (MQTT, then HTTP and HTTPS). Each Interaction Affordance and
the top-level `forms` array hold one, 16 or 128 Forms, the last of which is
the only compatible one: a relative `https` href resolved against the
Thing Description `base`. Every earlier Form uses a `coap` URI that neither
profile declares, so each input is the worst-case scan at that size; 128 is
the Runtime Form scan limit.


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



__Input: 1 Form__

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
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap; text-align: right">23.51 K</td>
    <td style="white-space: nowrap; text-align: right">42.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.87%</td>
    <td style="white-space: nowrap; text-align: right">42.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">54.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap; text-align: right">22.26 K</td>
    <td style="white-space: nowrap; text-align: right">44.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.44%</td>
    <td style="white-space: nowrap; text-align: right">44.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">57.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap; text-align: right">17.82 K</td>
    <td style="white-space: nowrap; text-align: right">56.11 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.18%</td>
    <td style="white-space: nowrap; text-align: right">56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">71.50 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap;text-align: right">23.51 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap; text-align: right">22.26 K</td>
    <td style="white-space: nowrap; text-align: right">1.06x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap; text-align: right">17.82 K</td>
    <td style="white-space: nowrap; text-align: right">1.32x</td>
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
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap">66.55 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap">69.88 KB</td>
    <td>1.05x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap">91.75 KB</td>
    <td>1.38x</td>
  </tr>
</table>



__Input: 128 Forms__

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
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap; text-align: right">231.57</td>
    <td style="white-space: nowrap; text-align: right">4.32 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.62%</td>
    <td style="white-space: nowrap; text-align: right">4.32 ms</td>
    <td style="white-space: nowrap; text-align: right">4.52 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap; text-align: right">223.97</td>
    <td style="white-space: nowrap; text-align: right">4.46 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.23%</td>
    <td style="white-space: nowrap; text-align: right">4.46 ms</td>
    <td style="white-space: nowrap; text-align: right">4.73 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap; text-align: right">164.34</td>
    <td style="white-space: nowrap; text-align: right">6.08 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.72%</td>
    <td style="white-space: nowrap; text-align: right">6.08 ms</td>
    <td style="white-space: nowrap; text-align: right">6.33 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap;text-align: right">231.57</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap; text-align: right">223.97</td>
    <td style="white-space: nowrap; text-align: right">1.03x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap; text-align: right">164.34</td>
    <td style="white-space: nowrap; text-align: right">1.41x</td>
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
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap">6.89 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap">7.35 MB</td>
    <td>1.07x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap">10.09 MB</td>
    <td>1.46x</td>
  </tr>
</table>



__Input: 16 Forms__

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
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap; text-align: right">1.79 K</td>
    <td style="white-space: nowrap; text-align: right">558.52 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.28%</td>
    <td style="white-space: nowrap; text-align: right">557.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">611.34 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap; text-align: right">1.74 K</td>
    <td style="white-space: nowrap; text-align: right">574.36 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.62%</td>
    <td style="white-space: nowrap; text-align: right">574.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">625.47 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap; text-align: right">1.28 K</td>
    <td style="white-space: nowrap; text-align: right">783.14 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.22%</td>
    <td style="white-space: nowrap; text-align: right">785 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">843.30 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap;text-align: right">1.79 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap; text-align: right">1.74 K</td>
    <td style="white-space: nowrap; text-align: right">1.03x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap; text-align: right">1.28 K</td>
    <td style="white-space: nowrap; text-align: right">1.4x</td>
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
    <td style="white-space: nowrap">select Action Form (invokeaction)</td>
    <td style="white-space: nowrap">890.16 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">select Property Form (readproperty)</td>
    <td style="white-space: nowrap">948.88 KB</td>
    <td>1.07x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">select top-level Form (readallproperties)</td>
    <td style="white-space: nowrap">1300.33 KB</td>
    <td>1.46x</td>
  </tr>
</table>