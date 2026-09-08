defmodule Wotex.Lab.Metrics.ReqSink do
  @moduledoc """
  The remote-write HTTP port implemented with the optional `Req` dependency.

  `write/3` POSTs an encoded request to the configured URL with the reserved
  remote-write headers, redirects and automatic retries disabled (retry
  policy belongs to the bridge), a bounded receive timeout and a response
  body cut at `:max_response_bytes` (4 KiB) so a server cannot flood the
  exporter. The credential is `nil`, `{:bearer, token}` or
  `{:basic, user, password}`; it becomes the `authorization` header of that
  one exchange and is never stored or echoed. A transport failure is
  classified as `:timeout` or `:unavailable` so the bridge can decide whether
  it is retryable. When `Req` is not present the sink reports
  `:client_unavailable` instead of raising. Configuration keys are
  `:url`, `:receive_timeout` (5,000 ms), `:connect_timeout` (5,000 ms),
  `:max_response_bytes` and `:finch`.
  """

  alias Wotex.Lab.Error

  @type credential :: nil | {:bearer, String.t()} | {:basic, String.t(), String.t()}
  @type result ::
          {:ok, %{status: pos_integer(), headers: [{String.t(), String.t()}]}}
          | {:error, Error.t()}

  @doc "Sends one remote-write body; the result carries the status and headers only."
  @spec write(%{body: binary(), headers: [{String.t(), String.t()}]}, credential(), map()) ::
          result()
  def write(%{body: body, headers: headers}, credential, config) when is_map(config) do
    with {:ok, url} <- url(config),
         {:ok, authorized} <- authorize(headers, credential),
         :ok <- available() do
      limit = Map.get(config, :max_response_bytes, 4_096)
      timeout = Map.get(config, :receive_timeout, 5_000)

      options =
        [
          method: :post,
          url: url,
          headers: authorized,
          body: body,
          redirect: false,
          retry: false,
          decode_body: false,
          receive_timeout: timeout,
          connect_options: [timeout: Map.get(config, :connect_timeout, 5_000)],
          into: &collect(&1, &2, limit)
        ] ++ finch(config)

      options |> Req.request() |> classify()
    end
  end

  def write(_request, _credential, _config),
    do: {:error, Error.new(:invalid_sink_request, :export, "request needs body and headers")}

  defp url(%{url: url}) when is_binary(url) and byte_size(url) > 0, do: {:ok, url}
  defp url(_config), do: {:error, Error.new(:invalid_sink_config, :export, "sink url is required")}

  defp authorize(headers, nil), do: {:ok, headers}

  defp authorize(headers, {:bearer, token}) when is_binary(token),
    do: {:ok, [{"authorization", "Bearer " <> token} | headers]}

  defp authorize(headers, {:basic, user, password}) when is_binary(user) and is_binary(password),
    do: {:ok, [{"authorization", "Basic " <> Base.encode64(user <> ":" <> password)} | headers]}

  defp authorize(_headers, _credential),
    do: {:error, Error.new(:unsupported_credential, :export, "credential shape is unsupported")}

  defp available do
    if Code.ensure_loaded?(Req),
      do: :ok,
      else: {:error, Error.new(:client_unavailable, :export, "Req is not available")}
  end

  defp collect({:data, data}, {req, %{body: body} = resp}, limit) when is_binary(body) do
    if byte_size(body) + byte_size(data) > limit,
      do: {:halt, {req, %{resp | body: binary_part(body, 0, byte_size(body))}}},
      else: {:cont, {req, %{resp | body: body <> data}}}
  end

  defp collect({:data, _data}, acc, _limit), do: {:halt, acc}

  defp classify({:ok, %{status: status, headers: headers}}) do
    flattened =
      Enum.flat_map(headers, fn {name, values} -> Enum.map(List.wrap(values), &{name, &1}) end)

    {:ok, %{status: status, headers: flattened}}
  end

  defp classify({:error, %{reason: :timeout}}),
    do: {:error, Error.new(:timeout, :export, "remote write timed out", class: :timeout)}

  defp classify({:error, _exception}),
    do: {:error, Error.new(:transport_failed, :export, "remote write failed", class: :unavailable)}

  defp finch(%{finch: name}) when is_atom(name) and not is_nil(name), do: [finch: name]
  defp finch(_config), do: []
end
