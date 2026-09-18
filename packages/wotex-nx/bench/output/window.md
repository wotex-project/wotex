# Observation admission and window resampling

One Property observation per feature and 1,000 ms step, with a deterministic
jitter below half a step, for 4, 16 and 64 features over 32, 128 and 512
steps (128, 2,048 and 32,768 observations). `Wotex.Nx.Observation.new/1`
admits every reading; `Wotex.Nx.Window.resample/4` selects schema-ordered
rows on the step grid with the `:latest` and `:nearest` strategies and a
maximum age of one step, with `:max_observations` raised to the input size.


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



__Input: 16 features x 128 rows__

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
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap; text-align: right">1101.45</td>
    <td style="white-space: nowrap; text-align: right">0.91 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.84%</td>
    <td style="white-space: nowrap; text-align: right">0.89 ms</td>
    <td style="white-space: nowrap; text-align: right">1.41 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap; text-align: right">333.57</td>
    <td style="white-space: nowrap; text-align: right">3.00 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.51%</td>
    <td style="white-space: nowrap; text-align: right">3.00 ms</td>
    <td style="white-space: nowrap; text-align: right">3.53 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap; text-align: right">325.87</td>
    <td style="white-space: nowrap; text-align: right">3.07 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.52%</td>
    <td style="white-space: nowrap; text-align: right">3.06 ms</td>
    <td style="white-space: nowrap; text-align: right">3.58 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap;text-align: right">1101.45</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap; text-align: right">333.57</td>
    <td style="white-space: nowrap; text-align: right">3.3x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap; text-align: right">325.87</td>
    <td style="white-space: nowrap; text-align: right">3.38x</td>
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
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap">5.45 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap">15.13 MB</td>
    <td>2.78x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap">15.56 MB</td>
    <td>2.86x</td>
  </tr>
</table>



__Input: 4 features x 32 rows__

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
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap; text-align: right">16.49 K</td>
    <td style="white-space: nowrap; text-align: right">60.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;32.36%</td>
    <td style="white-space: nowrap; text-align: right">54.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">132 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap; text-align: right">5.11 K</td>
    <td style="white-space: nowrap; text-align: right">195.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.77%</td>
    <td style="white-space: nowrap; text-align: right">192.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">249.05 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap; text-align: right">5.09 K</td>
    <td style="white-space: nowrap; text-align: right">196.35 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.91%</td>
    <td style="white-space: nowrap; text-align: right">195.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">250.04 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap;text-align: right">16.49 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap; text-align: right">5.11 K</td>
    <td style="white-space: nowrap; text-align: right">3.23x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap; text-align: right">5.09 K</td>
    <td style="white-space: nowrap; text-align: right">3.24x</td>
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
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap">348.44 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap">990.68 KB</td>
    <td>2.84x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap">1020.35 KB</td>
    <td>2.93x</td>
  </tr>
</table>



__Input: 64 features x 512 rows__

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
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap; text-align: right">66.37</td>
    <td style="white-space: nowrap; text-align: right">15.07 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.58%</td>
    <td style="white-space: nowrap; text-align: right">14.50 ms</td>
    <td style="white-space: nowrap; text-align: right">22.92 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap; text-align: right">20.30</td>
    <td style="white-space: nowrap; text-align: right">49.27 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.75%</td>
    <td style="white-space: nowrap; text-align: right">48.73 ms</td>
    <td style="white-space: nowrap; text-align: right">58.07 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap; text-align: right">19.77</td>
    <td style="white-space: nowrap; text-align: right">50.57 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.25%</td>
    <td style="white-space: nowrap; text-align: right">49.83 ms</td>
    <td style="white-space: nowrap; text-align: right">59.43 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap;text-align: right">66.37</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap; text-align: right">20.30</td>
    <td style="white-space: nowrap; text-align: right">3.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap; text-align: right">19.77</td>
    <td style="white-space: nowrap; text-align: right">3.36x</td>
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
    <td style="white-space: nowrap">Observation.new (every reading)</td>
    <td style="white-space: nowrap">87.25 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">resample :latest</td>
    <td style="white-space: nowrap">242.33 MB</td>
    <td>2.78x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">resample :nearest</td>
    <td style="white-space: nowrap">249.33 MB</td>
    <td>2.86x</td>
  </tr>
</table>