# Bounded JSON Merge Patch

A JSON Merge Patch that renames the Thing and adds a `description` and a
`minimum` to every Property, applied to synthetic Thing Descriptions with
one, 24 and 240 Properties. `Wotex.Directory.MergePatch.apply/3` measures
the bounded RFC 7396 merge alone with the default depth and node limits;
`Wotex.Directory.patch/5` adds authorization, retrieval from an in-process
snapshot repository, Discovery enrichment, revalidation of the merged Thing
Description, registration reconstruction and the conditional replacement.


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



__Input: 1 Property__

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
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap; text-align: right">501.50 K</td>
    <td style="white-space: nowrap; text-align: right">1.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;281.83%</td>
    <td style="white-space: nowrap; text-align: right">1.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap; text-align: right">6.92 K</td>
    <td style="white-space: nowrap; text-align: right">144.49 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.26%</td>
    <td style="white-space: nowrap; text-align: right">143.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">177.21 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap;text-align: right">501.50 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap; text-align: right">6.92 K</td>
    <td style="white-space: nowrap; text-align: right">72.46x</td>
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
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap">4.74 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap">302.09 KB</td>
    <td>63.7x</td>
  </tr>
</table>



__Input: 24 Properties__

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
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap; text-align: right">29.57 K</td>
    <td style="white-space: nowrap; text-align: right">33.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.61%</td>
    <td style="white-space: nowrap; text-align: right">32.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">44.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">910.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.36%</td>
    <td style="white-space: nowrap; text-align: right">911.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">988.72 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap;text-align: right">29.57 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">26.94x</td>
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
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap">0.0681 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap">2.03 MB</td>
    <td>29.84x</td>
  </tr>
</table>



__Input: 240 Properties__

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
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap; text-align: right">3.06 K</td>
    <td style="white-space: nowrap; text-align: right">0.33 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.91%</td>
    <td style="white-space: nowrap; text-align: right">0.33 ms</td>
    <td style="white-space: nowrap; text-align: right">0.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap; text-align: right">0.134 K</td>
    <td style="white-space: nowrap; text-align: right">7.48 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.66%</td>
    <td style="white-space: nowrap; text-align: right">7.47 ms</td>
    <td style="white-space: nowrap; text-align: right">7.80 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap;text-align: right">3.06 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap; text-align: right">0.134 K</td>
    <td style="white-space: nowrap; text-align: right">22.88x</td>
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
    <td style="white-space: nowrap">MergePatch.apply</td>
    <td style="white-space: nowrap">0.70 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Directory.patch (merge, revalidation, replacement)</td>
    <td style="white-space: nowrap">18.50 MB</td>
    <td>26.42x</td>
  </tr>
</table>