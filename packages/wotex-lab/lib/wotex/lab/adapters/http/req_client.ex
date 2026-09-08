# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Binding.HTTP.Client) do
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
    Configuration is closed and non-secret. In addition to finite receive,
    connect, handshake and line budgets, `:profile` is `:local` or `:hosted`.
    Hosted requests require an exact `:audience` origin and resolve through
    `:resolver`; private, link-local, metadata, multicast and mixed public/private
    answers are refused, and the admitted address is pinned through connect.
    TLS peer and hostname verification stays enabled. A local TLS fixture may
    name its CA with `:tls_ca_certfile`.
    """

    @behaviour Wotex.Binding.HTTP.Client

    alias Wotex.Binding.HTTP.{Headers, Request, Response}
    alias Wotex.Lab.Adapters.HTTP.SSE.Session
    alias Wotex.Lab.Network.Destination
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
      with {:ok, config} <- normalize_config(config),
           {:ok, destination} <- Destination.admit(Request.uri(request), config),
           {:ok, method} <- method(Request.method(request)),
           {:ok, headers} <- authorize(Request.headers(request), credential),
           {:ok, budget} <- budget(request, config) do
        limit = Request.max_response_bytes(request)

        options =
          [
            method: method,
            url: destination.url,
            headers: headers,
            body: Request.body(request),
            redirect: false,
            retry: false,
            decode_body: false,
            receive_timeout: budget,
            into: &collect(&1, &2, limit)
          ] ++ connection(config, destination, budget)

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
      with {:ok, config} <- normalize_config(config),
           {:ok, destination} <- Destination.admit(Request.uri(request), config),
           {:ok, method} <- method(Request.method(request)),
           {:ok, headers} <- authorize(Request.headers(request), credential),
           {:ok, budget} <- budget(request, config) do
        options =
          [
            method: method,
            url: destination.url,
            headers: headers,
            redirect: false,
            retry: false,
            decode_body: false,
            receive_timeout: :infinity
          ] ++ connection(config, destination, budget)

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

    defp connection(%{finch: nil}, destination, budget) do
      options =
        Keyword.put(
          destination.connect_options,
          :timeout,
          min(budget, destination.connect_options[:timeout])
        )

      [connect_options: options]
    end

    defp connection(%{finch: name}, _destination, _budget), do: [finch: name]

    defp flatten(headers) when is_map(headers),
      do: Enum.flat_map(headers, fn {name, values} -> Enum.map(List.wrap(values), &{name, &1}) end)

    defp normalize_config(config) when is_map(config) or is_list(config) do
      config = Map.new(config)

      normalized = %{
        receive_timeout: Map.get(config, :receive_timeout, 5_000),
        connect_timeout: Map.get(config, :connect_timeout, 5_000),
        handshake_timeout: Map.get(config, :handshake_timeout, 5_000),
        max_line_bytes: Map.get(config, :max_line_bytes, 65_536),
        finch: Map.get(config, :finch),
        profile: Map.get(config, :profile, :local),
        audience: Map.get(config, :audience),
        resolver: Map.get(config, :resolver, &:inet.getaddrs/2),
        tls_ca_certfile: Map.get(config, :tls_ca_certfile)
      }

      allowed = Map.keys(normalized)

      if Enum.all?(Map.keys(config), &(&1 in allowed)) and valid_config?(normalized),
        do: {:ok, normalized},
        else: {:error, :invalid_config}
    rescue
      _error -> {:error, :invalid_config}
    end

    defp normalize_config(_config), do: {:error, :invalid_config}

    defp valid_config?(config) do
      Enum.all?([
        timeout?(config.receive_timeout),
        timeout?(config.connect_timeout),
        timeout?(config.handshake_timeout),
        is_integer(config.max_line_bytes) and config.max_line_bytes in 1..1_048_576,
        is_nil(config.finch) or is_atom(config.finch),
        config.profile in [:local, :hosted],
        is_nil(config.audience) or is_binary(config.audience),
        is_function(config.resolver, 2),
        is_nil(config.tls_ca_certfile) or is_binary(config.tls_ca_certfile),
        config.profile == :local or is_nil(config.finch)
      ])
    end

    defp timeout?(value), do: is_integer(value) and value in 1..60_000
  end
end
