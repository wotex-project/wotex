defmodule WotexLabWorkbenchWeb.HostedInvestigationQueryController do
  @moduledoc false

  use WotexLabWorkbenchWeb, :controller

  alias Wotex.Lab.Metrics.Gateway
  alias WotexLabWorkbench.Investigation.HostedBroker

  @max_request_bytes 8 * 1_024
  @max_response_bytes 4 * 1_024
  @limits %{
    range_ms: 5 * 60 * 1_000,
    min_step_ms: 5_000,
    points: 61,
    output_bytes: 2_048,
    deadline_ms: 1_500,
    concurrent: 1
  }

  @doc false
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, request) when is_map(request) do
    capability = bearer(conn)

    with true <- loopback?(conn.remote_ip),
         true <- request_bytes(request) <= @max_request_bytes,
         {:ok, binding} <- HostedBroker.authorize_query(capability),
         {:ok, gateway} <- gateway(binding),
         {:ok, reference} <- Gateway.query(gateway, request) do
      try do
        answer(conn, gateway, reference)
      after
        _ = Gateway.revoke(gateway)
      end
    else
      false -> refuse(conn, :forbidden, "bridge request is not admitted")
      {:error, :bridge_denied} -> refuse(conn, :forbidden, "bridge capability is not active")
      {:error, error} -> refuse(conn, :unprocessable_entity, code(error))
    end
  end

  def create(conn, _), do: refuse(conn, :unprocessable_entity, "invalid_request")

  defp gateway(%{instance: instance, durable: durable})
       when is_binary(instance) and is_function(durable, 1) do
    Gateway.start_link(
      owner: self(),
      durable: durable,
      scope: %{instance: instance, session: session()},
      ttl_ms: 2_500,
      max_calls: 1,
      query_limits: @limits
    )
  end

  defp gateway(_), do: {:error, :bridge_denied}

  defp answer(conn, gateway, reference) do
    receive do
      {:metric_query, ^gateway, ^reference, {:ok, result}} ->
        with {:ok, encoded} <- Jason.encode(json(result)),
             true <- byte_size(encoded) <= @max_response_bytes do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, encoded)
        else
          _ -> refuse(conn, :unprocessable_entity, "output_too_large")
        end

      {:metric_query, ^gateway, ^reference, {:error, error}} ->
        refuse(conn, :unprocessable_entity, code(error))
    after
      1_750 ->
        _ = Gateway.cancel(gateway, reference)
        refuse(conn, :gateway_timeout, "deadline_exceeded")
    end
  end

  defp request_bytes(request) do
    case Jason.encode(request) do
      {:ok, encoded} -> byte_size(encoded)
      _ -> @max_request_bytes + 1
    end
  end

  defp code(%{code: code}) when is_atom(code), do: Atom.to_string(code)
  defp code(code) when is_atom(code), do: Atom.to_string(code)
  defp code(_), do: "query_unavailable"

  defp bearer(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> capability] -> capability
      _ -> nil
    end
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false

  defp session,
    do: "hosted-worker-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

  defp json(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp json(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {json_key(key), json(item)} end)

  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when is_atom(value), do: Atom.to_string(value)
  defp json(value) when is_tuple(value), do: json(Tuple.to_list(value))
  defp json(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)

  defp refuse(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{code: code})
  end
end
