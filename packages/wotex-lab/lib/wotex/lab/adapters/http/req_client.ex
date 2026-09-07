defmodule Wotex.Lab.Adapters.HTTP.ReqClient do
  @moduledoc """
  `Wotex.Binding.HTTP.Client` implemented with `Req` and `Finch`.

  Finite requests run with redirects and automatic retries disabled, a receive
  budget derived from the runtime deadline (or `:receive_timeout`), and a
  response body collected chunk by chunk that halts once it exceeds the
  request's `max_response_bytes`. Streams open through
  `Wotex.Lab.Adapters.HTTP.SSE.Session`, a process linked to the runtime
  subscription that parses SSE framing and sends frames to it.

  The credential resolved by the runtime is `nil`, `{:bearer, token}`,
  `{:basic, user, password}`, or a map of security names to those tuples; it
  becomes an `authorization` field for that one exchange and is never stored.
  Configuration is non-secret: `:receive_timeout` (5,000 ms), `:connect_timeout`
  (5,000 ms), `:handshake_timeout` (5,000 ms), `:max_line_bytes` (65,536), and
  `:finch` (an optional Finch instance name).
  """

  @behaviour Wotex.Binding.HTTP.Client

  alias Wotex.Binding.HTTP.{Headers, Request, Response}
  alias Wotex.Lab.Adapters.HTTP.SSE.Session
  alias Wotex.Lab.Telemetry
  alias Wotex.Runtime.Context

  @methods %{
    "GET" => :get,
    "PUT" => :put,
    "POST" => :post,
    "DELETE" => :delete,
    "PATCH" => :patch,
    "HEAD" => :head
  }

  @impl Wotex.Binding.HTTP.Client
  def request(%Request{} = request, credential, config) do
    config = normalize_config(config)

    with {:ok, method} <- method(Request.method(request)),
         {:ok, headers} <- authorize(Request.headers(request), credential),
         {:ok, budget} <- budget(request, config) do
      limit = Request.max_response_bytes(request)

      options =
        [
          method: method,
          url: Request.uri(request),
          headers: headers,
          body: Request.body(request),
          redirect: false,
          retry: false,
          decode_body: false,
          receive_timeout: budget,
          connect_options: [timeout: min(budget, config.connect_timeout)],
          into: &collect(&1, &2, limit)
        ] ++ finch(config)

      Telemetry.span(:http, :request, %{operation: method, profile: :http}, fn ->
        options |> Req.request() |> finite_response()
      end)
    end
  end

  defp finite_response({:ok, %Req.Response{body: :too_large}}), do: {:error, :response_too_large}

  defp finite_response({:ok, %Req.Response{status: status, headers: headers, body: body}})
       when is_binary(body) do
    with {:ok, fields} <- Headers.new(flatten(headers), :response) do
      Response.new(status, fields, body)
    end
  end

  defp finite_response({:ok, %Req.Response{}}), do: {:error, :unexpected_body}
  defp finite_response({:error, %{reason: :timeout}}), do: {:error, :timeout}
  defp finite_response({:error, _exception}), do: {:error, :transport_failed}

  @impl Wotex.Binding.HTTP.Client
  def subscribe(%Request{} = request, credential, owner, config) when is_pid(owner) do
    config = normalize_config(config)

    with {:ok, method} <- method(Request.method(request)),
         {:ok, headers} <- authorize(Request.headers(request), credential),
         {:ok, budget} <- budget(request, config) do
      options =
        [
          method: method,
          url: Request.uri(request),
          headers: headers,
          redirect: false,
          retry: false,
          decode_body: false,
          receive_timeout: :infinity,
          connect_options: [timeout: min(budget, config.connect_timeout)]
        ] ++ finch(config)

      parser = [
        max_line_bytes: config.max_line_bytes,
        max_event_bytes: Request.max_event_bytes(request)
      ]

      Telemetry.span(:http, :subscription, %{operation: method, profile: :http}, fn ->
        open_session(options, owner, parser, config.handshake_timeout)
      end)
    end
  end

  defp open_session(options, owner, parser, handshake_timeout) do
    with {:ok, session, status, response_headers} <-
           Session.open(options, owner, parser, handshake_timeout),
         {:ok, fields} <- Headers.new(response_headers, :response),
         {:ok, response} <- Response.new(status, fields, "") do
      {:ok, session, response}
    end
  end

  @impl Wotex.Binding.HTTP.Client
  def close(session, _config) when is_pid(session), do: Session.close(session)
  def close(_handle, _config), do: {:error, :invalid_handle}

  defp collect({:data, data}, {req, %Req.Response{body: body} = resp}, limit)
       when is_binary(body) do
    if byte_size(body) + byte_size(data) > limit do
      {:halt, {req, %{resp | body: :too_large}}}
    else
      {:cont, {req, %{resp | body: body <> data}}}
    end
  end

  defp collect({:data, _data}, acc, _limit), do: {:halt, acc}

  defp method(name) do
    case Map.fetch(@methods, name) do
      {:ok, method} -> {:ok, method}
      :error -> {:error, :unsupported_method}
    end
  end

  defp authorize(headers, nil), do: {:ok, headers}

  defp authorize(headers, {:bearer, token}) when is_binary(token),
    do: {:ok, [{"authorization", "Bearer " <> token} | headers]}

  defp authorize(headers, {:basic, user, password}) when is_binary(user) and is_binary(password),
    do: {:ok, [{"authorization", "Basic " <> Base.encode64(user <> ":" <> password)} | headers]}

  defp authorize(headers, credentials) when is_map(credentials) do
    Enum.reduce_while(credentials, {:ok, headers}, fn {_name, credential}, {:ok, acc} ->
      case authorize(acc, credential) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp authorize(_headers, _credential), do: {:error, :unsupported_credential}

  defp budget(request, config) do
    case Request.deadline(request) do
      nil ->
        {:ok, config.receive_timeout}

      deadline when is_integer(deadline) ->
        remaining(Context.remaining_ms(deadline, System.monotonic_time(:millisecond)))

      %DateTime{} = deadline ->
        remaining(Context.remaining_ms(deadline, DateTime.utc_now()))
    end
  end

  defp remaining(0), do: {:error, :timeout}
  defp remaining(ms) when is_integer(ms), do: {:ok, ms}
  defp remaining({:error, _reason}), do: {:error, :timeout}

  defp finch(%{finch: nil}), do: []
  defp finch(%{finch: name}), do: [finch: name]

  defp flatten(headers) when is_map(headers),
    do: Enum.flat_map(headers, fn {name, values} -> Enum.map(List.wrap(values), &{name, &1}) end)

  defp normalize_config(config) when is_map(config) or is_list(config) do
    config = Map.new(config)

    %{
      receive_timeout: Map.get(config, :receive_timeout, 5_000),
      connect_timeout: Map.get(config, :connect_timeout, 5_000),
      handshake_timeout: Map.get(config, :handshake_timeout, 5_000),
      max_line_bytes: Map.get(config, :max_line_bytes, 65_536),
      finch: Map.get(config, :finch)
    }
  end

  defp normalize_config(_config), do: normalize_config(%{})
end
