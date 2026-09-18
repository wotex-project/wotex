# Failure classification

The failure paths of `Wotex.Binding.HTTP.Transport` for a `readproperty`
request against an in-memory client, and of `decode_frame/3` for an
`observeproperty` stream. Each job asserts the code and retry class of
the returned `Wotex.Binding.HTTP.Error`: HTTP statuses 408, 429, 503 and
404, a client that reports a deadline expiry, a client that raises, a
truncated JSON response body, and an event above a 64-byte event limit.


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
    <td style="white-space: nowrap">oversized SSE event (protocol)</td>
    <td style="white-space: nowrap; text-align: right">40219.75 K</td>
    <td style="white-space: nowrap; text-align: right">0.0249 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2696.03%</td>
    <td style="white-space: nowrap; text-align: right">0.0208 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.0334 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">raising client (unavailable)</td>
    <td style="white-space: nowrap; text-align: right">193.50 K</td>
    <td style="white-space: nowrap; text-align: right">5.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;202.95%</td>
    <td style="white-space: nowrap; text-align: right">4.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">13.67 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">client deadline expiry (timeout)</td>
    <td style="white-space: nowrap; text-align: right">188.50 K</td>
    <td style="white-space: nowrap; text-align: right">5.31 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;282.71%</td>
    <td style="white-space: nowrap; text-align: right">4.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">13.29 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">status 503 (unavailable)</td>
    <td style="white-space: nowrap; text-align: right">154.49 K</td>
    <td style="white-space: nowrap; text-align: right">6.47 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;244.13%</td>
    <td style="white-space: nowrap; text-align: right">5.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">20.38 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">status 404 (permanent)</td>
    <td style="white-space: nowrap; text-align: right">153.64 K</td>
    <td style="white-space: nowrap; text-align: right">6.51 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;237.79%</td>
    <td style="white-space: nowrap; text-align: right">5.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">21.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">status 408 (timeout)</td>
    <td style="white-space: nowrap; text-align: right">153.22 K</td>
    <td style="white-space: nowrap; text-align: right">6.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;237.48%</td>
    <td style="white-space: nowrap; text-align: right">5.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">21.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">status 429 (rate_limited)</td>
    <td style="white-space: nowrap; text-align: right">153.11 K</td>
    <td style="white-space: nowrap; text-align: right">6.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;237.43%</td>
    <td style="white-space: nowrap; text-align: right">5.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">20.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">truncated JSON body (protocol)</td>
    <td style="white-space: nowrap; text-align: right">143.64 K</td>
    <td style="white-space: nowrap; text-align: right">6.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;87.58%</td>
    <td style="white-space: nowrap; text-align: right">6.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">26.71 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">oversized SSE event (protocol)</td>
    <td style="white-space: nowrap;text-align: right">40219.75 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">raising client (unavailable)</td>
    <td style="white-space: nowrap; text-align: right">193.50 K</td>
    <td style="white-space: nowrap; text-align: right">207.85x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">client deadline expiry (timeout)</td>
    <td style="white-space: nowrap; text-align: right">188.50 K</td>
    <td style="white-space: nowrap; text-align: right">213.37x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">status 503 (unavailable)</td>
    <td style="white-space: nowrap; text-align: right">154.49 K</td>
    <td style="white-space: nowrap; text-align: right">260.34x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">status 404 (permanent)</td>
    <td style="white-space: nowrap; text-align: right">153.64 K</td>
    <td style="white-space: nowrap; text-align: right">261.79x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">status 408 (timeout)</td>
    <td style="white-space: nowrap; text-align: right">153.22 K</td>
    <td style="white-space: nowrap; text-align: right">262.49x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">status 429 (rate_limited)</td>
    <td style="white-space: nowrap; text-align: right">153.11 K</td>
    <td style="white-space: nowrap; text-align: right">262.69x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">truncated JSON body (protocol)</td>
    <td style="white-space: nowrap; text-align: right">143.64 K</td>
    <td style="white-space: nowrap; text-align: right">280.01x</td>
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
    <td style="white-space: nowrap">oversized SSE event (protocol)</td>
    <td style="white-space: nowrap">0.148 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">raising client (unavailable)</td>
    <td style="white-space: nowrap">7.02 KB</td>
    <td>47.26x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">client deadline expiry (timeout)</td>
    <td style="white-space: nowrap">6.73 KB</td>
    <td>45.37x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">status 503 (unavailable)</td>
    <td style="white-space: nowrap">8.14 KB</td>
    <td>54.84x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">status 404 (permanent)</td>
    <td style="white-space: nowrap">8.14 KB</td>
    <td>54.84x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">status 408 (timeout)</td>
    <td style="white-space: nowrap">8.14 KB</td>
    <td>54.84x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">status 429 (rate_limited)</td>
    <td style="white-space: nowrap">8.14 KB</td>
    <td>54.84x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">truncated JSON body (protocol)</td>
    <td style="white-space: nowrap">10.38 KB</td>
    <td>69.95x</td>
  </tr>
</table>