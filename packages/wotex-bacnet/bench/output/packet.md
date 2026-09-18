# BACnet/IP datagram encoding and decoding

`Wotex.BACnet.IPv4Packet.encode/3` of confirmed ReadProperty and
WriteProperty (priority 8) service requests given as BACstack APDU values,
as the package's client builds them, and `Wotex.BACnet.IPv4Packet.decode/1`
of the unicast ReadProperty-ACK datagram. The Property values are a Real
present-value and CharacterString values of 64 bytes and 1 KiB. Encoding
includes BACstack APDU and NPCI encoding, the 1476-byte APDU limit and the
BVLL envelope; decoding checks the BVLL size and decodes the BVLC and NPCI
with the pinned SDK codecs while retaining the APDU bytes.


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
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap; text-align: right">22.95 M</td>
    <td style="white-space: nowrap; text-align: right">43.58 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2366.02%</td>
    <td style="white-space: nowrap; text-align: right">37.50 ns</td>
    <td style="white-space: nowrap; text-align: right">62.50 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap; text-align: right">1.60 M</td>
    <td style="white-space: nowrap; text-align: right">623.20 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1333.69%</td>
    <td style="white-space: nowrap; text-align: right">375 ns</td>
    <td style="white-space: nowrap; text-align: right">958 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap; text-align: right">0.37 M</td>
    <td style="white-space: nowrap; text-align: right">2705.28 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;187.88%</td>
    <td style="white-space: nowrap; text-align: right">2458 ns</td>
    <td style="white-space: nowrap; text-align: right">12708 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap;text-align: right">22.95 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap; text-align: right">1.60 M</td>
    <td style="white-space: nowrap; text-align: right">14.3x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap; text-align: right">0.37 M</td>
    <td style="white-space: nowrap; text-align: right">62.07x</td>
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
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap">0.68 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap">1.27 KB</td>
    <td>1.86x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap">2.02 KB</td>
    <td>2.97x</td>
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
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap; text-align: right">23.22 M</td>
    <td style="white-space: nowrap; text-align: right">43.07 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1977.91%</td>
    <td style="white-space: nowrap; text-align: right">37.50 ns</td>
    <td style="white-space: nowrap; text-align: right">62.50 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap; text-align: right">1.59 M</td>
    <td style="white-space: nowrap; text-align: right">627.93 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1310.28%</td>
    <td style="white-space: nowrap; text-align: right">375 ns</td>
    <td style="white-space: nowrap; text-align: right">1042 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap; text-align: right">0.85 M</td>
    <td style="white-space: nowrap; text-align: right">1170.72 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1104.52%</td>
    <td style="white-space: nowrap; text-align: right">708 ns</td>
    <td style="white-space: nowrap; text-align: right">2000 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap;text-align: right">23.22 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap; text-align: right">1.59 M</td>
    <td style="white-space: nowrap; text-align: right">14.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap; text-align: right">0.85 M</td>
    <td style="white-space: nowrap; text-align: right">27.18x</td>
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
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap">0.68 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap">1.27 KB</td>
    <td>1.86x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap">2.02 KB</td>
    <td>2.97x</td>
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
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap; text-align: right">11.71 M</td>
    <td style="white-space: nowrap; text-align: right">85.38 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5144.41%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap; text-align: right">1.64 M</td>
    <td style="white-space: nowrap; text-align: right">609.88 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1426.28%</td>
    <td style="white-space: nowrap; text-align: right">375 ns</td>
    <td style="white-space: nowrap; text-align: right">1125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap; text-align: right">1.17 M</td>
    <td style="white-space: nowrap; text-align: right">857.26 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1173.99%</td>
    <td style="white-space: nowrap; text-align: right">541 ns</td>
    <td style="white-space: nowrap; text-align: right">1750 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap;text-align: right">11.71 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap; text-align: right">1.64 M</td>
    <td style="white-space: nowrap; text-align: right">7.14x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap; text-align: right">1.17 M</td>
    <td style="white-space: nowrap; text-align: right">10.04x</td>
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
    <td style="white-space: nowrap">decode ReadProperty-ACK datagram</td>
    <td style="white-space: nowrap">0.68 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode ReadProperty request</td>
    <td style="white-space: nowrap">1.19 KB</td>
    <td>1.75x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">encode WriteProperty request</td>
    <td style="white-space: nowrap">1.76 KB</td>
    <td>2.59x</td>
  </tr>
</table>