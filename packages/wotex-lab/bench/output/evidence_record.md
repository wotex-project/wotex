# Evidence record admission, canonical digests and fixture trees

`Wotex.Lab.Evidence.Record` and `Wotex.Lab.Evidence.Digest` over run
records with 8, 128 and 1,024 fixture digests, input references and
assertions (1,024 is the record's collection bound), 24 dependencies
(the eight WoTEx packages with `archive: :missing`, 16 Hex packages with
an archive digest), the default runner budgets and this host's
toolchain strings. The fixtures are files of about 2 KiB in seven lane
directories of a temporary tree.

`new: validate and scan` is `Wotex.Lab.Evidence.Record.new/1`: every
field's shape and bound, the `sha256:` form of every digest, and the
scan of every value for callbacks, process identities, filesystem paths
and credential material. `from_map: read back` is
`Wotex.Lab.Evidence.Record.from_map/1` on the record's string-keyed map,
which reads keys back only as existing atoms and validates again.
`digest: canonical encoding and SHA-256` is
`Wotex.Lab.Evidence.Record.digest/1`:
`Wotex.Lab.Evidence.Record.to_map/1`, the canonical encoding with
`Wotex.JSON.encode/1` and the SHA-256 of the bytes. `digest the fixture
tree` is `Wotex.Lab.Evidence.Digest.tree/2`: reading and digesting every
fixture file and hashing the sorted `path\0digest` lines. Every job
compares its result with the value computed before the run.


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



__Input: 1024 fixtures__

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
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap; text-align: right">325.89</td>
    <td style="white-space: nowrap; text-align: right">3.07 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.47%</td>
    <td style="white-space: nowrap; text-align: right">3.03 ms</td>
    <td style="white-space: nowrap; text-align: right">3.46 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap; text-align: right">242.29</td>
    <td style="white-space: nowrap; text-align: right">4.13 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.10%</td>
    <td style="white-space: nowrap; text-align: right">4.10 ms</td>
    <td style="white-space: nowrap; text-align: right">4.43 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap; text-align: right">238.92</td>
    <td style="white-space: nowrap; text-align: right">4.19 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.46%</td>
    <td style="white-space: nowrap; text-align: right">4.17 ms</td>
    <td style="white-space: nowrap; text-align: right">5.02 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap; text-align: right">20.71</td>
    <td style="white-space: nowrap; text-align: right">48.28 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.36%</td>
    <td style="white-space: nowrap; text-align: right">47.80 ms</td>
    <td style="white-space: nowrap; text-align: right">55.46 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap;text-align: right">325.89</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap; text-align: right">242.29</td>
    <td style="white-space: nowrap; text-align: right">1.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap; text-align: right">238.92</td>
    <td style="white-space: nowrap; text-align: right">1.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap; text-align: right">20.71</td>
    <td style="white-space: nowrap; text-align: right">15.73x</td>
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
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap">5.09 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap">1.78 MB</td>
    <td>0.35x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap">1.87 MB</td>
    <td>0.37x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap">9.71 MB</td>
    <td>1.91x</td>
  </tr>
</table>



__Input: 128 fixtures__

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
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap; text-align: right">2.26 K</td>
    <td style="white-space: nowrap; text-align: right">442.36 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.57%</td>
    <td style="white-space: nowrap; text-align: right">425.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">644.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap; text-align: right">1.64 K</td>
    <td style="white-space: nowrap; text-align: right">609.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.28%</td>
    <td style="white-space: nowrap; text-align: right">608.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">675.59 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap; text-align: right">1.58 K</td>
    <td style="white-space: nowrap; text-align: right">634.72 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.46%</td>
    <td style="white-space: nowrap; text-align: right">629.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">743.65 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap; text-align: right">0.190 K</td>
    <td style="white-space: nowrap; text-align: right">5264.49 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.25%</td>
    <td style="white-space: nowrap; text-align: right">5235.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5799.93 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap;text-align: right">2.26 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap; text-align: right">1.64 K</td>
    <td style="white-space: nowrap; text-align: right">1.38x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap; text-align: right">1.58 K</td>
    <td style="white-space: nowrap; text-align: right">1.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap; text-align: right">0.190 K</td>
    <td style="white-space: nowrap; text-align: right">11.9x</td>
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
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap">773.16 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap">274.03 KB</td>
    <td>0.35x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap">288.24 KB</td>
    <td>0.37x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap">1267.42 KB</td>
    <td>1.64x</td>
  </tr>
</table>



__Input: 8 fixtures__

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
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap; text-align: right">11.11 K</td>
    <td style="white-space: nowrap; text-align: right">89.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.74%</td>
    <td style="white-space: nowrap; text-align: right">89.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">116.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap; text-align: right">7.76 K</td>
    <td style="white-space: nowrap; text-align: right">128.81 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.85%</td>
    <td style="white-space: nowrap; text-align: right">126.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">164.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap; text-align: right">7.57 K</td>
    <td style="white-space: nowrap; text-align: right">132.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.45%</td>
    <td style="white-space: nowrap; text-align: right">132.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">162.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap; text-align: right">2.23 K</td>
    <td style="white-space: nowrap; text-align: right">447.61 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.70%</td>
    <td style="white-space: nowrap; text-align: right">442.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">536.97 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap;text-align: right">11.11 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap; text-align: right">7.76 K</td>
    <td style="white-space: nowrap; text-align: right">1.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap; text-align: right">7.57 K</td>
    <td style="white-space: nowrap; text-align: right">1.47x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap; text-align: right">2.23 K</td>
    <td style="white-space: nowrap; text-align: right">4.98x</td>
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
    <td style="white-space: nowrap">digest: canonical encoding and SHA-256</td>
    <td style="white-space: nowrap">180.42 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">new: validate and scan</td>
    <td style="white-space: nowrap">65.95 KB</td>
    <td>0.37x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">from_map: read back</td>
    <td style="white-space: nowrap">70.71 KB</td>
    <td>0.39x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">digest the fixture tree</td>
    <td style="white-space: nowrap">124.79 KB</td>
    <td>0.69x</td>
  </tr>
</table>